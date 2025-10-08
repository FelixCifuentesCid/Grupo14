import 'package:flutter/material.dart';
import '../core/api.dart';
import '../widgets/common.dart';

class CreateDesignScreen extends StatefulWidget {
  const CreateDesignScreen({super.key});
  @override
  State<CreateDesignScreen> createState() => _CreateDesignScreenState();
}

class _CreateDesignScreenState extends State<CreateDesignScreen> {
  final _title = TextEditingController();
  final _desc  = TextEditingController();
  final _img   = TextEditingController();
  final _price = TextEditingController();
  bool _busy = false;

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(ko('Título es requerido')); return; }
    final String? imageUrl = _img.text.trim().isEmpty ? null : _img.text.trim();
    final String? description = _desc.text.trim().isEmpty ? null : _desc.text.trim();
    final int? price = _price.text.trim().isEmpty ? null : int.tryParse(_price.text.trim());

    setState(() => _busy = true);
    try {
      await Api.createDesign(title: title, description: description, imageUrl: imageUrl, price: price);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(ok('Diseño creado'));
      Navigator.pop(context, true); // refresh flag
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(ko(e.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _img.text.trim();
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo diseño')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Título *')),
          const Gap(10),
          TextField(controller: _desc, decoration: const InputDecoration(labelText: 'Descripción'), maxLines: 3),
          const Gap(10),
          TextField(controller: _img, decoration: const InputDecoration(labelText: 'URL de imagen (opcional)')),
          const Gap(10),
          TextField(controller: _price, decoration: const InputDecoration(labelText: 'Precio (opcional, número)'), keyboardType: TextInputType.number),
          const Gap(16),
          if (preview.isNotEmpty) AspectRatio(
            aspectRatio: 1,
            child: Image.network(preview, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0x11000000))),
          ),
          const Gap(16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Publicar'),
          ),
        ],
      ),
    );
  }
}
