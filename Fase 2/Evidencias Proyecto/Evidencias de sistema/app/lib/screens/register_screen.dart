import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/pns.dart';
import '../widgets/common.dart';
import 'catalog_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState()=> _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _email = TextEditingController();
  final _pass  = TextEditingController();
  final _name  = TextEditingController();
  String _role = 'client';
  bool _busy   = false;

  Future<void> _submit() async {
    setState(()=> _busy = true);
    final err = await Api.register(
      email: _email.text.trim(),
      pass:  _pass.text,
      name:  _name.text,
      role:  _role,
    );
    setState(()=> _busy = false);
    if (!mounted) return;

    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(ko(err));
      return;
    }

    // En tu Api.register, si el backend devuelve 201, ya haces login interno.
    // ✅ Apenas hay sesión, registramos token FCM y vamos al catálogo.
    try {
      await Pns.registerCurrentToken();
    } catch (_) {}

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(ok('¡Bienvenido/a!'));
    Navigator.pushReplacementNamed(context, CatalogScreen.route);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          TextField(controller: _name,  decoration: const InputDecoration(labelText:'Nombre')),
          const Gap(10),
          TextField(controller: _email, decoration: const InputDecoration(labelText:'Email')),
          const Gap(10),
          TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText:'Password')),
          const Gap(10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value:'client', label: Text('Cliente'), icon: Icon(Icons.person_outline)),
              ButtonSegment(value:'artist', label: Text('Artista'), icon: Icon(Icons.brush_outlined)),
            ],
            selected: {_role},
            onSelectionChanged: (s)=> setState(()=> _role = s.first),
          ),
          const Gap(20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(height:18, width:18, child:CircularProgressIndicator(strokeWidth:2))
                : const Text('Registrar'),
          ),
        ],
      ),
    );
  }
}
