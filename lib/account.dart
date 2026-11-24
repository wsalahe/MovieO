import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const sbUrl = 'https://rlpfwpvdcvofcirmbkom.supabase.co';
const sbKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJscGZ3cHZkY3ZvZmNpcm1ia29tIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTU1MTI2MDQsImV4cCI6MjExMTA4ODYwNH0.kb_kCIfHpKyitSW8HhFNN5yNhbGTg1gk72St6kt7tXY';

class Account {
  static String? access, refresh, uid, email;
  static Map<String, dynamic> profile = {
    'display_name': '',
    'language': 'en',
    'autoplay': true,
    'quality': 'auto',
  };

  static bool get signedIn => access != null && uid != null;

  static Map<String, String> _h([bool auth = true]) => {
        'apikey': sbKey,
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${auth && access != null ? access : sbKey}',
      };

  static Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    if (access == null) {
      await p.remove('sb_session');
    } else {
      await p.setString('sb_session',
          jsonEncode({'a': access, 'r': refresh, 'u': uid, 'e': email}));
    }
  }

  static void _take(Map<String, dynamic> j) {
    access = j['access_token'] as String?;
    refresh = j['refresh_token'] as String?;
    final u = j['user'] as Map<String, dynamic>?;
    uid = u?['id'] as String?;
    email = u?['email'] as String?;
  }

  static String _err(http.Response r) {
    try {
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      return '${j['msg'] ?? j['error_description'] ?? j['message'] ?? r.body}';
    } catch (_) {
      return 'Error ${r.statusCode}';
    }
  }

  static Future<bool> restore() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString('sb_session');
    if (s == null) return false;
    final j = jsonDecode(s) as Map<String, dynamic>;
    access = j['a'] as String?;
    refresh = j['r'] as String?;
    uid = j['u'] as String?;
    email = j['e'] as String?;
    try {
      final r = await http.post(
          Uri.parse('$sbUrl/auth/v1/token?grant_type=refresh_token'),
          headers: _h(false),
          body: jsonEncode({'refresh_token': refresh}));
      if (r.statusCode == 200) {
        _take(jsonDecode(r.body) as Map<String, dynamic>);
        await _save();
      } else if (r.statusCode == 400 || r.statusCode == 401) {
        access = null;
        await _save();
        return false;
      }
    } catch (_) {}
    if (signedIn) await loadProfile();
    return signedIn;
  }

  static Future<String?> signIn(String e, String pw) async {
    try {
      final r = await http.post(
          Uri.parse('$sbUrl/auth/v1/token?grant_type=password'),
          headers: _h(false),
          body: jsonEncode({'email': e, 'password': pw}));
      if (r.statusCode != 200) return _err(r);
      _take(jsonDecode(r.body) as Map<String, dynamic>);
      await _save();
      await loadProfile();
      return null;
    } catch (x) {
      return 'No connection';
    }
  }

  static Future<String?> signUp(String e, String pw, String name) async {
    try {
      final r = await http.post(Uri.parse('$sbUrl/auth/v1/signup'),
          headers: _h(false),
          body: jsonEncode({
            'email': e,
            'password': pw,
            'data': {'display_name': name}
          }));
      if (r.statusCode != 200) return _err(r);
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (j['access_token'] == null) {
        return 'Check your email to confirm, then sign in';
      }
      _take(j);
      await _save();
      profile['display_name'] = name;
      await saveProfile();
      return null;
    } catch (x) {
      return 'No connection';
    }
  }

  static Future<void> loadProfile() async {
    try {
      final r = await http.get(
          Uri.parse('$sbUrl/rest/v1/profiles?id=eq.$uid&select=*'),
          headers: _h());
      if (r.statusCode == 200) {
        final l = jsonDecode(r.body) as List;
        if (l.isNotEmpty) {
          profile = Map<String, dynamic>.from(l.first as Map);
        }
      }
    } catch (_) {}
  }

  static Future<bool> saveProfile() async {
    try {
      final body = {
        'id': uid,
        'display_name': profile['display_name'],
        'language': profile['language'],
        'autoplay': profile['autoplay'],
        'quality': profile['quality'],
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      final h = _h();
      h['Prefer'] = 'resolution=merge-duplicates';
      final r = await http.post(Uri.parse('$sbUrl/rest/v1/profiles'),
          headers: h, body: jsonEncode(body));
      return r.statusCode == 201 || r.statusCode == 200 || r.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  static Future<void> signOut() async {
    try {
      await http.post(Uri.parse('$sbUrl/auth/v1/logout'), headers: _h());
    } catch (_) {}
    access = null;
    refresh = null;
    uid = null;
    email = null;
    await _save();
  }
}

class AuthPage extends StatefulWidget {
  final VoidCallback onDone;
  const AuthPage({super.key, required this.onDone});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final e = TextEditingController(), p = TextEditingController(), n = TextEditingController();
  bool signup = false, busy = false;
  String? err;

  Future<void> _go() async {
    setState(() { busy = true; err = null; });
    final r = signup
        ? await Account.signUp(e.text.trim(), p.text, n.text.trim())
        : await Account.signIn(e.text.trim(), p.text);
    if (!mounted) return;
    setState(() { busy = false; err = r; });
    if (r == null) widget.onDone();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('MovieO',
                  style: TextStyle(
                      color: Color(0xFFE50914),
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3)),
              const SizedBox(height: 24),
              if (signup)
                TextField(controller: n, decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder())),
              if (signup) const SizedBox(height: 12),
              TextField(controller: e, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: p, obscureText: true, decoration: const InputDecoration(labelText: 'Password (6+ characters)', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              if (err != null) Text(err!, style: const TextStyle(color: Colors.redAccent)),
              const SizedBox(height: 8),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      onPressed: busy ? null : _go,
                      child: Text(busy ? '...' : signup ? 'Create account' : 'Sign in'))),
              TextButton(
                  onPressed: () => setState(() { signup = !signup; err = null; }),
                  child: Text(signup ? 'Have an account? Sign in' : 'New here? Create account')),
            ]),
          ),
        ),
      );
}

class SettingsPage extends StatefulWidget {
  final VoidCallback onSignedOut;
  const SettingsPage({super.key, required this.onSignedOut});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final name = TextEditingController(text: '${Account.profile['display_name'] ?? ''}');

  Future<void> _save() async {
    Account.profile['display_name'] = name.text.trim();
    final ok = await Account.saveProfile();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? 'Saved' : 'Could not save')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.email), title: Text(Account.email ?? '')),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Display name', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          const Text('Playback', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Autoplay'),
              value: Account.profile['autoplay'] == true,
              onChanged: (v) => setState(() => Account.profile['autoplay'] = v)),
          DropdownButtonFormField<String>(
            value: '${Account.profile['quality'] ?? 'auto'}',
            decoration: const InputDecoration(labelText: 'Video quality', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'auto', child: Text('Auto')),
              DropdownMenuItem(value: 'high', child: Text('High')),
              DropdownMenuItem(value: 'data', child: Text('Data saver')),
            ],
            onChanged: (v) => setState(() => Account.profile['quality'] = v ?? 'auto'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: '${Account.profile['language'] ?? 'en'}',
            decoration: const InputDecoration(labelText: 'Language', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'en', child: Text('English')),
              DropdownMenuItem(value: 'ar', child: Text('العربية')),
            ],
            onChanged: (v) => setState(() => Account.profile['language'] = v ?? 'en'),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Save changes')),
          const SizedBox(height: 24),
          OutlinedButton.icon(
              onPressed: () async {
                await Account.signOut();
                if (context.mounted) {
                  Navigator.pop(context);
                  widget.onSignedOut();
                }
              },
              icon: const Icon(Icons.logout),
              label: const Text('Sign out')),
          const SizedBox(height: 16),
          const Center(child: Text('MovieO 1.1', style: TextStyle(color: Colors.white38))),
        ]),
      );
}
