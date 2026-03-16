import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'db_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RealEstateApp());
}

class RealEstateApp extends StatelessWidget {
  const RealEstateApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TKR Hub',
      theme: ThemeData(
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: Colors.grey[100],
        appBarTheme: const AppBarTheme(elevation: 0, backgroundColor: Colors.teal),
      ),
      home: const AuthCheck(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// --- SECURITY: Auth Check ---
class AuthCheck extends StatefulWidget {
  const AuthCheck({Key? key}) : super(key: key);
  @override
  _AuthCheckState createState() => _AuthCheckState();
}
class _AuthCheckState extends State<AuthCheck> {
  @override
  void initState() {
    super.initState();
    _checkLogin();
  }
  _checkLogin() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool isLog = prefs.getBool('isLoggedIn') ?? false;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => isLog ? const DashboardScreen() : const LoginScreen()));
  }
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

// --- LOGIN SCREEN ---
class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);
  @override
  _LoginScreenState createState() => _LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen> {
  final _userC = TextEditingController();
  final _passC = TextEditingController();
  
  String _hashPassword(String password) {
    var bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  _login() async {
    if (_userC.text == 'admin' && _passC.text == '1478963') { // Hardcoded default for offline initialization
      SharedPreferences prefs = await SharedPreferences.getInstance();
      prefs.setBool('isLoggedIn', true);
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardScreen()));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('မှားယွင်းနေပါသည်!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.teal[700],
      body: Center(
        child: Card(
          margin: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.real_estate_agent, size: 80, color: Colors.teal),
                const SizedBox(height: 20),
                const Text('TKR HUB', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                TextField(controller: _userC, decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder())),
                const SizedBox(height: 15),
                TextField(controller: _passC, obscureText: true, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
                const SizedBox(height: 20),
                SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: _login, child: const Text('LOGIN', style: TextStyle(fontSize: 18)))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- DASHBOARD (Bottom Nav) ---
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);
  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}
class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  final List<Widget> _screens = [const PropertiesScreen(), const BuyersScreen(), const SettingsScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Properties'),
          BottomNavigationBarItem(icon: Icon(Icons.group), label: 'Buyers'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

// --- PROPERTIES SCREEN ---
class PropertiesScreen extends StatefulWidget {
  const PropertiesScreen({Key? key}) : super(key: key);
  @override
  _PropertiesScreenState createState() => _PropertiesScreenState();
}
class _PropertiesScreenState extends State<PropertiesScreen> {
  List<Map<String, dynamic>> _properties = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }
  _loadData() async {
    final data = await DBHelper.instance.readAll('properties');
    setState(() => _properties = data);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Properties (အိမ်ခြံမြေများ)'),
        actions: [
          IconButton(icon: const Icon(Icons.sync), onPressed: () async {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Syncing...')));
            String msg = await DBHelper.instance.syncData();
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
            _loadData();
          })
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddPropertyScreen())).then((_) => _loadData()),
      ),
      body: _properties.isEmpty ? const Center(child: Text('ဒေတာမရှိသေးပါ။')) : ListView.builder(
        itemCount: _properties.length,
        itemBuilder: (context, index) {
          final p = _properties[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: ListTile(
              leading: p['image_path'] != null 
                  ? Image.file(File(p['image_path'].split('|')[0]), width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.image)) 
                  : const Icon(Icons.home, size: 50),
              title: Text(p['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${p['asking_price']} သိန်း | 📍 ${p['location']}'),
              trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () async {
                await DBHelper.instance.delete('properties', p['id']);
                _loadData();
              }),
            ),
          );
        },
      ),
    );
  }
}

// --- ADD PROPERTY SCREEN (Optimized Forms & Image Compression) ---
class AddPropertyScreen extends StatefulWidget {
  const AddPropertyScreen({Key? key}) : super(key: key);
  @override
  _AddPropertyScreenState createState() => _AddPropertyScreenState();
}
class _AddPropertyScreenState extends State<AddPropertyScreen> {
  final _titleC = TextEditingController();
  final _priceC = TextEditingController();
  final _locC = TextEditingController();
  final _mapC = TextEditingController();
  String _imagePath = '';

  _pickImage() async {
    // Builder 2.0 Security/Optimization: Compress image to 70% quality automatically
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image != null) setState(() => _imagePath = image.path);
  }

  _save() async {
    if (_titleC.text.isEmpty || _priceC.text.isEmpty) return;
    await DBHelper.instance.insert('properties', {
      'title': _titleC.text,
      'asking_price': double.tryParse(_priceC.text) ?? 0,
      'location': _locC.text,
      'map_link': _mapC.text,
      'image_path': _imagePath.isEmpty ? null : _imagePath,
      'status': 'Available'
    });
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Property')),
      body: ListView(
        padding: const EdgeInsets.all(15),
        children: [
          TextField(controller: _titleC, decoration: const InputDecoration(labelText: 'ခေါင်းစဉ်', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _priceC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'ခေါ်ဈေး (သိန်း)', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _locC, decoration: const InputDecoration(labelText: 'တည်နေရာ', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _mapC, decoration: const InputDecoration(labelText: 'Google Map Link (Optional)', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _pickImage, 
            icon: const Icon(Icons.image), 
            label: Text(_imagePath.isEmpty ? 'ဓာတ်ပုံရွေးရန်' : 'ပုံရွေးချယ်ပြီးပါပြီ')
          ),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: _save, style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(15)), child: const Text('SAVE DATA', style: TextStyle(fontSize: 16))),
        ],
      ),
    );
  }
}

// --- BUYERS SCREEN ---
class BuyersScreen extends StatefulWidget {
  const BuyersScreen({Key? key}) : super(key: key);
  @override
  _BuyersScreenState createState() => _BuyersScreenState();
}
class _BuyersScreenState extends State<BuyersScreen> {
  List<Map<String, dynamic>> _buyers = [];
  @override
  void initState() { super.initState(); _loadData(); }
  _loadData() async {
    final data = await DBHelper.instance.readAll('buyers');
    setState(() => _buyers = data);
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buyers List')),
      body: _buyers.isEmpty ? const Center(child: Text('ဝယ်သူမရှိသေးပါ။')) : ListView.builder(
        itemCount: _buyers.length,
        itemBuilder: (context, index) {
          final b = _buyers[index];
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(b['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Budget: ${b['budget']} သိန်း | 📞 ${b['phone']}'),
            trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () async {
              await DBHelper.instance.delete('buyers', b['id']);
              _loadData();
            }),
          );
        },
      ),
    );
  }
}

// --- SETTINGS SCREEN ---
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.cloud_sync, color: Colors.teal),
            title: const Text('Force Cloud Sync'),
            subtitle: const Text('Supabase သို့ Data များပို့/ယူမည်'),
            onTap: () async {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Syncing...')));
              String msg = await DBHelper.instance.syncData();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: () async {
              SharedPreferences prefs = await SharedPreferences.getInstance();
              prefs.clear();
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
          ),
        ],
      ),
    );
  }
}
