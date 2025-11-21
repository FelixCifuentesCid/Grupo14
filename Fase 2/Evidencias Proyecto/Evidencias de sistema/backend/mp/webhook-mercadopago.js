// webhook-mercadopago.js (reemplazo completo)
const mercadopago = require('mercadopago');
const crypto = require('crypto');
const axios = require('axios');
const config = require('./config'); // opcional

const { MercadoPagoConfig, Payment } = mercadopago;

// ENV
const ACCESS_TOKEN =
  (config && config.access_token) || process.env.ACCESS_TOKEN;
const WEBHOOK_SECRET_RAW =
  ((config && config.webhook_secret) || process.env.WEBHOOK_SECRET || '').trim();
const BACKEND_BASE = process.env.BACKEND_BASE || 'http://167.114.145.34:8000';
const BACKEND_WEBHOOK_TOKEN = process.env.BACKEND_WEBHOOK_TOKEN || '';

// Utils HMAC
function isHex(str) {
  return typeof str === 'string' && /^[0-9a-f]+$/i.test(str) && str.length % 2 === 0;
}
function hmacHex(keyBuf, data) {
  return crypto.createHmac('sha256', keyBuf).update(data).digest('hex');
}
function safeEq(a, b) {
  try {
    const ba = Buffer.from(a, 'hex');
    const bb = Buffer.from(b, 'hex');
    return ba.length === bb.length && crypto.timingSafeEqual(ba, bb);
  } catch {
    return false;
  }
}
function normalizeDataId(dataId) {
  const s = (dataId || '').toString();
  return /[A-Za-z]/.test(s) ? s.toLowerCase() : s;
}

module.exports = function webhookMercadoPago(req, res) {
  try {
    const xSignature = req.headers['x-signature'];
    const xRequestId = req.headers['x-request-id'];

    // *** CLAVE: usar SIEMPRE el id de la QUERY para firmar y para consultar ***
    const urlDataId = (req.query['data.id'] || '').toString();
    const bodyDataId = (req.body?.data?.id || '').toString(); // fallback
    const dataID = normalizeDataId(urlDataId || bodyDataId);

    if (!xSignature || !xRequestId || !dataID) {
      console.warn('Incomplete webhook data', {
        hasSignature: !!xSignature,
        hasRequestId: !!xRequestId,
        hasDataId: !!dataID,
      });
      return res.status(400).send('Invalid request');
    }

    // Parse x-signature
    const parts = xSignature.split(/,|;/);
    let ts, hash;
    for (const part of parts) {
      const [kRaw, vRaw] = (part || '').split('=');
      if (!kRaw || !vRaw) continue;
      const k = kRaw.trim();
      const v = vRaw.trim();
      if (k === 'ts') ts = v;
      if (k === 'v1') hash = v;
    }
    if (!ts || !hash) {
      console.warn('Missing ts or v1 in x-signature', { xSignature });
      return res.status(400).send('Invalid signature');
    }

    // Manifest EXACTO
    const manifest = `id:${dataID};request-id:${xRequestId};ts:${ts};`;

    // Probar clave como HEX y como UTF-8
    const candidates = [];
    if (isHex(WEBHOOK_SECRET_RAW)) candidates.push(Buffer.from(WEBHOOK_SECRET_RAW, 'hex'));
    candidates.push(Buffer.from(WEBHOOK_SECRET_RAW, 'utf8'));

    let ok = false;
    let usedMode = null;
    for (const [i, keyBuf] of candidates.entries()) {
      const calc = hmacHex(keyBuf, manifest);
      if (safeEq(calc, hash) || calc === hash) {
        ok = true;
        usedMode = isHex(WEBHOOK_SECRET_RAW) && i === 0 ? 'hex' : 'utf8';
        break;
      }
    }
    if (!ok) {
      const calcUtf8 = hmacHex(Buffer.from(WEBHOOK_SECRET_RAW, 'utf8'), manifest);
      const calcHex = isHex(WEBHOOK_SECRET_RAW)
        ? hmacHex(Buffer.from(WEBHOOK_SECRET_RAW, 'hex'), manifest)
        : null;
      console.warn('HMAC verification failed', {
        receivedHash: hash,
        manifest,
        secretLooksHex: isHex(WEBHOOK_SECRET_RAW),
        calc_with_utf8_key: calcUtf8,
        calc_with_hex_key: calcHex,
      });
      return res.status(400).send('Invalid signature');
    }

    // ---- Firma OK: procesar con el ID correcto ----
    const notifType = (req.query.type || req.body?.type || '').toString();

    processPaymentNotification({ id: dataID, type: notifType })
      .then(() => {
        console.log('Webhook processed successfully', {
          dataID,
          requestId: xRequestId,
          hmacKeyMode: usedMode,
        });
        res.status(200).send('Ok');
      })
      .catch((err) => {
        console.error('Webhook processing error', err?.message || err);
        res.status(500).send('Internal server error');
      });
  } catch (error) {
    console.error('Webhook processing error', {
      error: error.message,
      stack: error.stack,
    });
    res.status(500).send('Internal server error');
  }
};

async function processPaymentNotification({ id, type }) {
  const client = new MercadoPagoConfig({ accessToken: ACCESS_TOKEN });
  const payment = new Payment(client);

  // Solo si es de tipo "payment" y tenemos id
  if ((type || '').toLowerCase() === 'payment' && id) {
    try {
      const dataPayment = await payment.get({ id });
      console.log('Pago -> ', {
        id: dataPayment.id,
        status: dataPayment.status,
        external_reference: dataPayment.external_reference,
      });

      const appointmentId = dataPayment.external_reference;
      const status = dataPayment.status; // approved | rejected | pending | ...

      if (appointmentId) {
        try {
          await axios.post(
            `${BACKEND_BASE}/payments/mercadopago`,
            {
              appointment_id: appointmentId,
              status,
              payment_id: dataPayment.id,
              payer_email: dataPayment.payer?.email || null,
            },
            {
              headers: BACKEND_WEBHOOK_TOKEN
                ? { 'X-Webhook-Token': BACKEND_WEBHOOK_TOKEN }
                : {},
              timeout: 5000,
            }
          );
          console.log('Backend principal notificado OK', { appointmentId, status });
        } catch (err) {
          console.error('Error notificando backend principal', err?.response?.data || err.message);
        }
      } else {
        console.warn('Sin external_reference; no se puede reconciliar pago con reserva');
      }
    } catch (e) {
      console.error(`Error consultando pago en MP id=${id}`, e?.response?.data || e.message);
    }
  }

  if ((type || '').toLowerCase() === 'stop_delivery_op_wh') {
    console.log('Fraude -> ', id);
  }
}
