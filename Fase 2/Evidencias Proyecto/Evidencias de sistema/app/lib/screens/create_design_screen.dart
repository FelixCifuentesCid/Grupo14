// lib/screens/create_design_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../widgets/common.dart';

class CreateDesignScreen extends StatefulWidget {
  /// Si viene `design`, la pantalla funciona como "Editar diseño"
  final Map<String, dynamic>? design;

  const CreateDesignScreen({super.key, this.design});

  @override
  State<CreateDesignScreen> createState() => _CreateDesignScreenState();
}

class _CreateDesignScreenState extends State<CreateDesignScreen> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _img = TextEditingController();
  final _price = TextEditingController();

  bool _busy = false;
  bool _uploadingImage = false;

  final ImagePicker _picker = ImagePicker();

  bool get _isEditing => widget.design != null;

  @override
  void initState() {
    super.initState();
    final d = widget.design;
    if (d != null) {
      _title.text = d['title']?.toString() ?? '';
      _desc.text = d['description']?.toString() ?? '';
      _img.text = d['image_url']?.toString() ?? '';

      final price = d['price'];
      if (price != null) {
        final p = int.tryParse(price.toString());
        if (p != null) {
          _price.text = p.toString();
        }
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _img.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadImage() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      setState(() {
        _uploadingImage = true;
      });

      final bytes = await picked.readAsBytes();
      final b64 = base64Encode(bytes);

      // Usa el endpoint existente /upload/image
      final url = await Api.uploadImageBase64(b64);

      if (!mounted) return;
      setState(() {
        _img.text = url;
        _uploadingImage = false;
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(ok('Imagen subida correctamente'));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadingImage = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(ko('Error subiendo imagen: $e'));
    }
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(ko('Título es requerido'));
      return;
    }

    final String? imageUrl =
        _img.text.trim().isEmpty ? null : _img.text.trim();
    final String? description =
        _desc.text.trim().isEmpty ? null : _desc.text.trim();
    final int? price = _price.text.trim().isEmpty
        ? null
        : int.tryParse(_price.text.trim());

    setState(() => _busy = true);
    try {
      if (_isEditing && widget.design?['id'] != null) {
        // EDITAR
        await Api.updateDesign(
          id: widget.design!['id'] as int,
          title: title,
          description: description,
          imageUrl: imageUrl,
          price: price,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(ok('Diseño actualizado'));
      } else {
        // CREAR NUEVO
        await Api.createDesign(
          title: title,
          description: description,
          imageUrl: imageUrl,
          price: price,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(ok('Diseño creado'));
      }

      if (!mounted) return;
      // true = indica al caller que debe refrescar
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(ko(e.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _img.text.trim();
    final editing = _isEditing;

    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Editar diseño' : 'Nuevo diseño'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Título *'),
          ),
          const Gap(10),
          TextField(
            controller: _desc,
            decoration: const InputDecoration(
              labelText: 'Descripción',
            ),
            maxLines: 3,
          ),
          const Gap(10),

          // ==== NUEVO BLOQUE: seleccionar imagen desde galería ====
          Text(
            'Imagen del diseño',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const Gap(8),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: _uploadingImage ? null : _pickAndUploadImage,
                  child: Text(
                    preview.isEmpty
                        ? 'Elegir desde galería'
                        : 'Cambiar imagen',
                  ),
                ),
              ),
              if (_uploadingImage) ...[
                const SizedBox(width: 12),
                const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          const Gap(10),

          TextField(
            controller: _price,
            decoration: const InputDecoration(
              labelText: 'Precio (opcional, número)',
            ),
            keyboardType: TextInputType.number,
          ),
          const Gap(16),

          if (preview.isNotEmpty)
            AspectRatio(
              aspectRatio: 1,
              child: Image.network(
                preview,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const ColoredBox(color: Color(0x11000000)),
              ),
            ),
          if (preview.isNotEmpty) const Gap(16),

          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    editing ? 'Guardar cambios' : 'Publicar',
                  ),
          ),
        ],
      ),
    );
  }
}