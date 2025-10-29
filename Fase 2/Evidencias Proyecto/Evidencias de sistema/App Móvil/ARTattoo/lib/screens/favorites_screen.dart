import 'package:flutter/material.dart';
import '../core/api.dart';
import '../widgets/common.dart';
import 'design_detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  static const route = '/favorites';
  const FavoritesScreen({super.key});
  @override State<FavoritesScreen> createState()=> _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  late Future<List<Map<String,dynamic>>> _f;
  @override void initState(){ super.initState(); _f = Api.myFavorites(); }
  Future<void> _refresh() async { setState(()=> _f = Api.myFavorites()); }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: const Text('Mis favoritos')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder(
          future: _f,
          builder: (_, snap){
            if (snap.connectionState != ConnectionState.done) return const Busy();
            final items = (snap.data as List<Map<String,dynamic>>?) ?? [];
            if (items.isEmpty) return const Center(child: Text('Sin favoritos aún'));
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __)=> const Divider(height: 1),
              itemBuilder: (_, i){
                final d = items[i];
                return ListTile(
                  leading: (d['image_url']!=null && (d['image_url'] as String).isNotEmpty)
                    ? Image.network(d['image_url'], width: 56, height: 56, fit: BoxFit.cover)
                    : const SizedBox(width:56,height:56),
                  title: Text(d['title'] ?? '—'),
                  subtitle: Text('${d['artist_name'] ?? '—'} • ❤ ${d['likes_count'] ?? 0}'),
                  onTap: ()=> Navigator.push(_,
                    MaterialPageRoute(builder: (__)=>
                      DesignDetailScreen(design: {
                        "id": d["design_id"],
                        "title": d["title"],
                        "description": d["description"],
                        "image_url": d["image_url"],
                        "price": d["price"],
                        "artist_id": d["artist_id"],
                        "artist_name": d["artist_name"],
                      })
                    )),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
