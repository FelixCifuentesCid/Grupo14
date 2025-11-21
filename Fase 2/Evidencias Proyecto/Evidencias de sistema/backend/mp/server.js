// server.js
require('dotenv').config();
const express = require('express');
const app = express();
const cors = require('cors');
const mercadopago = require('mercadopago');
const axios = require('axios');

const { MercadoPagoConfig, Preference } = mercadopago;

// ENV
const PORT = parseInt(process.env.PORT || '8001', 10);
const BACKEND_BASE = process.env.BACKEND_BASE || 'http://167.114.145.34:8000';
const BACKEND_WEBHOOK_TOKEN = process.env.BACKEND_WEBHOOK_TOKEN || '';
const ACCESS_TOKEN = process.env.ACCESS_TOKEN;
const PUBLIC_BASE = process.env.PUBLIC_BASE || 'https://pipops.cl'; // dominio público https

// MP client
const client = new MercadoPagoConfig({
  accessToken: ACCESS_TOKEN,
  options: { timeout: 5000 },
});

app.use(express.urlencoded({ extended: false }));
app.use(express.json());
app.use(cors({ origin: '*' }));

app.get('/', (_req, res) => res.status(200).send('<h1>Server running</h1>'));

// Rutas existentes (si mantienes el webhook)
try { require('./routes')(app); } catch (_) { /* opcional */ }

/**
 * Crea preferencia para una cita
 * body: { appointment_id: number }
 * resp: { id, init_point }
 */
app.post('/payments/create', async (req, res) => {
  try {
    const { appointment_id } = req.body || {};
    if (!appointment_id) {
      return res.status(400).json({ msg: 'appointment_id requerido' });
    }

    // Traer info de la cita (opcional)
    let apt = {};
    try {
      const r = await axios.get(`${BACKEND_BASE}/appointments/${appointment_id}`, {
        headers: BACKEND_WEBHOOK_TOKEN ? { 'X-Webhook-Token': BACKEND_WEBHOOK_TOKEN } : {},
        timeout: 5000,
      });
      apt = r.data || {};
    } catch (_) { /* no bloquea */ }

    const title = apt.title || `Reserva #${appointment_id}`;
    const description = apt.description || `Pago de reserva #${appointment_id}`;
    const unitPrice = Number(apt.price ?? apt.amount ?? 0) || 1000;

    const preference = new Preference(client);

    // Deep link a tu app móvil
    const returnBase = 'artattoo://pay-result';
    const body = {
      items: [
        {
          id: String(appointment_id),
          title,
          description,
          quantity: 1,
          currency_id: 'CLP',
          unit_price: unitPrice,
        },
      ],
      external_reference: String(appointment_id),
      back_urls: {
        success: `${returnBase}?status=approved&apt=${appointment_id}`,
        failure: `${returnBase}?status=failure&apt=${appointment_id}`,
        pending: `${returnBase}?status=pending&apt=${appointment_id}`,
      },
      auto_return: 'approved',
      // Si no quieres restricciones, comenta este bloque
      // payment_methods: {
      //   installments: 6,
      //   excluded_payment_methods: [{ id: 'visa' }],
      // },
      // Aunque ya no dependas del webhook, lo dejamos por redundancia (HTTPS dominio)
      notification_url: `${PUBLIC_BASE}/webhook/mercadopago?source_news=webhooks`,
    };

    const requestOptions = { integratorId: 'dev_24c65fb163bf11ea96500242ac130004' };
    const mpRes = await preference.create({ body, requestOptions });

    return res.json({
      id: mpRes.id,
      init_point: mpRes.sandbox_init_point || mpRes.init_point,
    });
  } catch (e) {
    console.error('payments/create error:', e?.response?.data || e.message);
    return res.status(500).json({ msg: 'Error creando preferencia' });
  }
});

/**
 * Confirmación bajo demanda (sin depender del webhook)
 * body: { appointment_id: number, payment_id?: string }
 * - Si hay pago approved (por id o por external_reference) -> notifica backend y devuelve {paid:true}
 */
app.post('/payments/confirm', async (req, res) => {
  try {
    const { appointment_id, payment_id } = req.body || {};
    if (!appointment_id) return res.status(400).json({ msg: 'appointment_id requerido' });

    // 1) Si vino payment_id explícito: consultar primero por ese id
    if (payment_id) {
      const p = await getPaymentByIdSafe(String(payment_id));
      if (p && p.status === 'approved') {
        await notifyBackendPaid(String(appointment_id), p);
        return res.json({ paid: true, status: 'approved', payment_id: p.id });
      }
    }

    // 2) Buscar por external_reference (appointment_id)
    const found = await searchPaymentsByExternalRef(String(appointment_id));
    // Orden descendente por fecha ya viene si se usa sort/criteria; aseguramos por las dudas
    found.sort((a, b) => new Date(b.date_created) - new Date(a.date_created));
    const approved = found.find(p => (p.status || '').toLowerCase() === 'approved');
    const latest = found[0];

    if (approved) {
      await notifyBackendPaid(String(appointment_id), approved);
      return res.json({ paid: true, status: 'approved', payment_id: approved.id });
    }
    if (latest) {
      return res.json({ paid: false, status: latest.status || 'pending' });
    }
    return res.json({ paid: false, status: 'not_found' });
  } catch (e) {
    console.error('payments/confirm error:', e?.response?.data || e.message);
    return res.status(500).json({ msg: 'Error confirmando pago' });
  }
});

// -------- Helpers --------

async function getPaymentByIdSafe(id) {
  try {
    const url = `https://api.mercadopago.com/v1/payments/${encodeURIComponent(id)}`;
    const { data } = await axios.get(url, {
      headers: { Authorization: `Bearer ${ACCESS_TOKEN}` },
      timeout: 5000,
    });
    return data;
  } catch (_) {
    return null;
  }
}

async function searchPaymentsByExternalRef(external_reference) {
  try {
    const url = `https://api.mercadopago.com/v1/payments/search`;
    const { data } = await axios.get(url, {
      headers: { Authorization: `Bearer ${ACCESS_TOKEN}` },
      timeout: 5000,
      params: { external_reference, sort: 'date_created', criteria: 'desc' },
    });
    return Array.isArray(data?.results) ? data.results : [];
  } catch (e) {
    console.error('searchPaymentsByExternalRef error:', e?.response?.data || e.message);
    return [];
  }
}

async function notifyBackendPaid(appointmentId, payment) {
  try {
    await axios.post(
      `${BACKEND_BASE}/payments/mercadopago`,
      {
        appointment_id: appointmentId,
        status: 'approved',
        payment_id: payment?.id || null,
        payer_email: payment?.payer?.email || null,
      },
      {
        headers: BACKEND_WEBHOOK_TOKEN ? { 'X-Webhook-Token': BACKEND_WEBHOOK_TOKEN } : {},
        timeout: 5000,
      }
    );
    console.log('Backend principal notificado OK', { appointmentId });
  } catch (err) {
    console.error('Error notificando backend principal', err?.response?.data || err.message);
  }
}

app.listen(PORT, () => {
  console.log(`Payments server running on Port ${PORT}`);
});
