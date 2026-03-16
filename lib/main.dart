import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
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
      title: 'TKR ERP',
      theme: ThemeData(primarySwatch: Colors.teal, scaffoldBackgroundColor: Colors.grey[100]),
      home: const AuthCheck(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// --- UTILS ---
class Utils {
  static String formatNum(dynamic numStr) {
    if (numStr == null || numStr.toString().isEmpty) return '0';
    double val = double.tryParse(numStr.toString()) ?? 0;
    return NumberFormat('#,###').format(val);
  }

  static String timeAgo(String? dateStr) {
    if (dateStr == null) return '';
    DateTime date = DateTime.tryParse(dateStr) ?? DateTime.now();
    Duration diff = DateTime.now().difference(date);
    if (diff.inDays > 365) return '${(diff.inDays / 365).floor()} year(s) ago';
    if (diff.inDays > 30) return '${(diff.inDays / 30).floor()} month(s) ago';
    if (diff.inDays > 0) return '${diff.inDays} day(s) ago';
    if (diff.inHours > 0) return '${diff.inHours} hour(s) ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes} min(s) ago';
    return 'Just now';
  }

  static Future<void> dial(BuildContext context, String phones) async {
    if (phones.isEmpty) return;
    List<String> nums = phones.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (nums.length == 1) {
      launchUrl(Uri.parse('tel:${nums[0]}'));
    } else if (nums.isNotEmpty) {
      showModalBottomSheet(
        context: context,
        builder: (c) => ListView(
          shrinkWrap: true,
          children: nums.map((n) => ListTile(
            leading: const Icon(Icons.phone, color: Colors.green),
            title: Text(n),
            onTap: () { Navigator.pop(c); launchUrl(Uri.parse('tel:$n')); },
          )).toList(),
        ),
      );
    }
  }

  static void showUndo(BuildContext context, String table, int id, VoidCallback onRestore) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Deleted to Recycle Bin'),
      action: SnackBarAction(label: 'UNDO', onPressed: () async {
        await DBHelper.instance.restore(table, id);
        onRestore();
      }),
      duration: const Duration(seconds: 4),
    ));
  }
}

// --- AUTH ---
class AuthCheck extends StatefulWidget { const AuthCheck({Key? key}) : super(key: key); @override _AuthCheckState createState() => _AuthCheckState(); }
class _AuthCheckState extends State<AuthCheck> {
  @override void initState() { super.initState(); _check(); }
  _check() async {
    SharedPreferences p = await SharedPreferences.getInstance();
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => p.getBool('isLog') ?? false ? const Dashboard() : const Login()));
  }
  @override Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class Login extends StatefulWidget { const Login({Key? key}) : super(key: key); @override _LoginState createState() => _LoginState(); }
class _LoginState extends State<Login> {
  final _u = TextEditingController(), _p = TextEditingController();
  _login() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String savedP = prefs.getString('pass') ?? sha256.convert(utf8.encode('1478963')).toString();
    if (_u.text == 'admin' && sha256.convert(utf8.encode(_p.text)).toString() == savedP) {
      prefs.setBool('isLog', true);
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const Dashboard()));
    } else { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('မှားယွင်းနေပါသည်'))); }
  }
  @override Widget build(BuildContext context) => Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.real_estate_agent, size: 80, color: Colors.teal), const SizedBox(height: 20),
    TextField(controller: _u, decoration: const InputDecoration(labelText: 'Username')),
    TextField(controller: _p, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
    const SizedBox(height: 20), ElevatedButton(onPressed: _login, child: const Text('LOGIN'))
  ]))));
}

// --- DASHBOARD ---
class Dashboard extends StatefulWidget { const Dashboard({Key? key}) : super(key: key); @override _DashboardState createState() => _DashboardState(); }
class _DashboardState extends State<Dashboard> {
  int _idx = 0;
  final List<Widget> _sc = [const PropsView(), const BuyersView(), const OwnersView(), const BinView(), const SettingsView()];
  @override Widget build(BuildContext context) => Scaffold(
    body: _sc[_idx],
    bottomNavigationBar: BottomNavigationBar(
      currentIndex: _idx, type: BottomNavigationBarType.fixed, selectedItemColor: Colors.teal, unselectedItemColor: Colors.grey,
      onTap: (i) => setState(() => _idx = i),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Props'),
        BottomNavigationBarItem(icon: Icon(Icons.group), label: 'Buyers'),
        BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Owners'),
        BottomNavigationBarItem(icon: Icon(Icons.delete), label: 'Bin'),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Setup')
      ],
    ),
  );
}

// --- DYNAMIC DROPDOWN ---
class DynamicDropdown extends StatefulWidget {
  final String label; final String? val; final List<String> opts; final Function(String) onChanged; final String table; final String col;
  const DynamicDropdown({Key? key, required this.label, this.val, required this.opts, required this.onChanged, required this.table, required this.col}) : super(key: key);
  @override _DynDropState createState() => _DynDropState();
}
class _DynDropState extends State<DynamicDropdown> {
  List<String> _items = []; String? _current;
  @override void initState() { super.initState(); _load(); }
  _load() async {
    List<String> dbItems = await DBHelper.instance.getUniqueValues(widget.table, widget.col);
    Set<String> all = {...widget.opts, ...dbItems};
    _items = all.toList()..removeWhere((e) => e.isEmpty);
    if (widget.val != null && widget.val!.isNotEmpty && !_items.contains(widget.val)) _items.add(widget.val!);
    setState(() => _current = (widget.val == null || widget.val!.isEmpty) ? null : widget.val);
  }
  _addNew() async {
    TextEditingController c = TextEditingController();
    await showDialog(context: context, builder: (_) => AlertDialog(
      title: Text('Add New ${widget.label}'),
      content: TextField(controller: c, decoration: const InputDecoration(hintText: 'Type here')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Add'))]
    ));
    if (c.text.isNotEmpty) {
      setState(() { _items.add(c.text); _current = c.text; });
      widget.onChanged(c.text);
    }
  }
  @override Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(labelText: widget.label, border: const OutlineInputBorder(), isDense: true),
      value: _current,
      items: [
        ..._items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        const DropdownMenuItem(value: 'ADD_NEW', child: Text('+ Add New', style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)))
      ],
      onChanged: (v) { if (v == 'ADD_NEW') _addNew(); else { setState(() => _current = v); widget.onChanged(v!); } }
    );
  }
}

// --- OWNER AUTOCOMPLETE ---
class OwnerAutocomplete extends StatefulWidget {
  final String? initial; final Function(String) onSelected;
  const OwnerAutocomplete({Key? key, this.initial, required this.onSelected}) : super(key: key);
  @override _OwnerAutoState createState() => _OwnerAutoState();
}
class _OwnerAutoState extends State<OwnerAutocomplete> {
  List<String> _owners = []; final _c = TextEditingController();
  @override void initState() { super.initState(); _c.text = widget.initial ?? ''; _load(); }
  _load() async { final data = await DBHelper.instance.readAll('owners'); setState(() => _owners = data.map((e) => e['name'].toString()).toList()); }
  @override Widget build(BuildContext context) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: widget.initial ?? ''),
      optionsBuilder: (v) => v.text.isEmpty ? const Iterable<String>.empty() : _owners.where((o) => o.toLowerCase().contains(v.text.toLowerCase())),
      onSelected: (s) => widget.onSelected(s),
      fieldViewBuilder: (ctx, c, f, onS) {
        c.addListener(() { widget.onSelected(c.text); });
        return TextField(controller: c, focusNode: f, decoration: InputDecoration(labelText: 'Owner Name (Auto-add if new)', border: const OutlineInputBorder(), isDense: true, suffixIcon: IconButton(icon: const Icon(Icons.add), onPressed: (){})));
      },
    );
  }
}

// --- FORMS ---
class PropForm extends StatefulWidget {
  final Map<String, dynamic>? item; const PropForm({Key? key, this.item}) : super(key: key);
  @override _PropFormState createState() => _PropFormState();
}
class _PropFormState extends State<PropForm> {
  final _t = TextEditingController(), _df = TextEditingController(), _db = TextEditingController(), _ds = TextEditingController(), _dn = TextEditingController();
  final _ap = TextEditingController(), _bp = TextEditingController(), _ml = TextEditingController(), _rm = TextEditingController();
  String _pType = 'အိမ်', _hType = '', _lType = '', _oName = '', _loc = '', _st = 'Available';
  List<String> _imgs = [];

  @override void initState() {
    super.initState();
    if (widget.item != null) {
      final i = widget.item!;
      _t.text = i['title'] ?? ''; _pType = i['property_type'] ?? 'အိမ်'; _hType = i['house_type'] ?? '';
      _lType = i['land_type'] ?? ''; _oName = i['owner_name'] ?? ''; _df.text = (i['dim_front'] ?? '').toString();
      _db.text = (i['dim_back'] ?? '').toString(); _ds.text = (i['dim_left'] ?? '').toString(); 
      _dn.text = (i['dim_right'] ?? '').toString(); 
      _st = i['status'] ?? 'Available'; _ap.text = (i['asking_price'] ?? '').toString(); _bp.text = (i['bottom_price'] ?? '').toString();
      _loc = i['location'] ?? ''; _ml.text = i['map_link'] ?? ''; _rm.text = i['remark'] ?? '';
      _imgs = (i['image_path'] ?? '').toString().split('|').where((e) => e.isNotEmpty).toList();
    }
  }

  _pick() async {
    final List<XFile> picked = await ImagePicker().pickMultiImage(imageQuality: 70);
    for (var f in picked) {
      if (File(f.path).lengthSync() <= 5 * 1024 * 1024) { setState(() => _imgs.add(f.path)); }
      else { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Skipped image > 5MB'))); }
    }
  }

  _save() async {
    if (_t.text.isEmpty || _ap.text.isEmpty) return;
    if (_oName.isNotEmpty) {
      var exist = await DBHelper.instance.database.then((db) => db.query('owners', where: 'name=?', whereArgs: [_oName]));
      if (exist.isEmpty) await DBHelper.instance.insert('owners', {'name': _oName, 'phone': '', 'remark': 'Auto-added'});
    }
    Map<String, dynamic> data = {
      'title': _t.text, 'property_type': _pType, 'house_type': _pType == 'အိမ်' ? _hType : '', 'land_type': _lType, 'owner_name': _oName,
      'dim_front': double.tryParse(_df.text) ?? 0, 'dim_back': double.tryParse(_db.text) ?? 0, 'dim_left': double.tryParse(_ds.text) ?? 0, 'dim_right': double.tryParse(_dn.text) ?? 0,
      'status': _st, 'asking_price': double.tryParse(_ap.text.replaceAll(',', '')) ?? 0, 'bottom_price': double.tryParse(_bp.text.replaceAll(',', '')) ?? 0,
      'location': _loc, 'map_link': _ml.text, 'remark': _rm.text, 'image_path': _imgs.join('|')
    };
    if (widget.item == null) await DBHelper.instance.insert('properties', data);
    else await DBHelper.instance.update('properties', data, widget.item!['id']);
    Navigator.pop(context, true);
  }

  @override Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('Property Form')), body: ListView(padding: const EdgeInsets.all(12), children: [
      TextField(controller: _t, decoration: const InputDecoration(labelText: 'Title*', border: OutlineInputBorder(), isDense:true)), const SizedBox(height:10),
      DropdownButtonFormField<String>(value: _pType, items: ['အိမ်', 'ခြံမြေ'].map((e)=>DropdownMenuItem(value:e,child:Text(e))).toList(), onChanged: (v)=>setState(()=>_pType=v!), decoration: const InputDecoration(labelText: 'Property Type', border: OutlineInputBorder(), isDense:true)), const SizedBox(height:10),
      if (_pType == 'အိမ်') ...[DynamicDropdown(label: 'House Type', val: _hType, opts: const ['၁ထပ်တိုက်', '၂ထပ်တိုက်'], table: 'properties', col: 'house_type', onChanged: (v)=>_hType=v), const SizedBox(height:10)],
      DynamicDropdown(label: 'Land Type', val: _lType, opts: const ['လယ်မြေ', 'ရွာမြေ', 'မြို့မြေ'], table: 'properties', col: 'land_type', onChanged: (v)=>_lType=v), const SizedBox(height:10),
      OwnerAutocomplete(initial: _oName, onSelected: (v)=>_oName=v), const SizedBox(height:10),
      Row(children: [Expanded(child: TextField(controller: _df, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Front (ft)', border: OutlineInputBorder(), isDense:true))), const SizedBox(width:5), Expanded(child: TextField(controller: _db, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Back (ft)', border: OutlineInputBorder(), isDense:true)))]), const SizedBox(height:10),
      Row(children: [Expanded(child: TextField(controller: _ds, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'South (ft)', border: OutlineInputBorder(), isDense:true))), const SizedBox(width:5), Expanded(child: TextField(controller: _dn, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'North (ft)', border: OutlineInputBorder(), isDense:true)))]), const SizedBox(height:10),
      DynamicDropdown(label: 'Status', val: _st, opts: const ['Available', 'Pending', 'Sold'], table: 'properties', col: 'status', onChanged: (v)=>_st=v), const SizedBox(height:10),
      Row(children: [Expanded(child: TextField(controller: _ap, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Ask Price*', border: OutlineInputBorder(), isDense:true))), const SizedBox(width:5), Expanded(child: TextField(controller: _bp, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Bottom Price', border: OutlineInputBorder(), isDense:true)))]), const SizedBox(height:10),
      DynamicDropdown(label: 'Location', val: _loc, opts: const ['ကောင်ရွေးရွာ', 'နားဘောင်ရွာ'], table: 'properties', col: 'location', onChanged: (v)=>_loc=v), const SizedBox(height:10),
      Row(children: [Expanded(child: TextField(controller: _ml, decoration: const InputDecoration(labelText: 'Map Link', border: OutlineInputBorder(), isDense:true))), IconButton(icon: const Icon(Icons.map, color:Colors.teal), onPressed: (){ if(_ml.text.isNotEmpty) launchUrl(Uri.parse(_ml.text)); })]), const SizedBox(height:10),
      TextField(controller: _rm, maxLines: 2, decoration: const InputDecoration(labelText: 'Remark', border: OutlineInputBorder(), isDense:true)), const SizedBox(height:10),
      ElevatedButton.icon(icon: const Icon(Icons.photo), label: const Text('Pick Images (<5MB)'), onPressed: _pick),
      if (_imgs.isNotEmpty) SizedBox(height: 80, child: ListView(scrollDirection: Axis.horizontal, children: _imgs.map((p)=>Padding(padding: const EdgeInsets.only(right:5), child: Stack(children: [Image.file(File(p), width: 80, height: 80, fit: BoxFit.cover), Positioned(right:0,child: InkWell(onTap:()=>setState(()=>_imgs.remove(p)), child: const Icon(Icons.cancel, color: Colors.red)))]))).toList())),
      const SizedBox(height:20), ElevatedButton(onPressed: _save, style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(15)), child: const Text('SAVE PROPERTY'))
    ]));
  }
}

class BuyerForm extends StatefulWidget {
  final Map<String, dynamic>? item; const BuyerForm({Key? key, this.item}) : super(key: key);
  @override _BuyerFormState createState() => _BuyerFormState();
}
class _BuyerFormState extends State<BuyerForm> {
  final _n = TextEditingController(), _p = TextEditingController(), _b = TextEditingController(), _r = TextEditingController(), _l = TextEditingController(), _rm = TextEditingController();
  @override void initState() {
    super.initState(); if(widget.item!=null){ final i=widget.item!; _n.text=i['name']??''; _p.text=i['phone']??''; _b.text=(i['budget']??'').toString(); _r.text=i['requirement']??''; _l.text=i['location']??''; _rm.text=i['remark']??'';}
  }
  _save() async {
    if (_n.text.isEmpty) return;
    Map<String, dynamic> d = {'name': _n.text, 'phone': _p.text, 'budget': double.tryParse(_b.text.replaceAll(',', '')) ?? 0, 'requirement': _r.text, 'location': _l.text, 'remark': _rm.text};
    widget.item == null ? await DBHelper.instance.insert('buyers', d) : await DBHelper.instance.update('buyers', d, widget.item!['id']);
    Navigator.pop(context, true);
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Buyer Form')), body: ListView(padding: const EdgeInsets.all(12), children: [
    TextField(controller: _n, decoration: const InputDecoration(labelText: 'Name*', border: OutlineInputBorder())), const SizedBox(height:10),
    TextField(controller: _p, decoration: const InputDecoration(labelText: 'Phone(s) - comma separated', border: OutlineInputBorder())), const SizedBox(height:10),
    TextField(controller: _b, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Budget', border: OutlineInputBorder())), const SizedBox(height:10),
    TextField(controller: _r, decoration: const InputDecoration(labelText: 'Requirement', border: OutlineInputBorder())), const SizedBox(height:10),
    TextField(controller: _l, decoration: const InputDecoration(labelText: 'Location', border: OutlineInputBorder())), const SizedBox(height:10),
    TextField(controller: _rm, decoration: const InputDecoration(labelText: 'Remark', border: OutlineInputBorder())), const SizedBox(height:20),
    ElevatedButton(onPressed: _save, child: const Text('SAVE BUYER', style: TextStyle(padding: EdgeInsets.all(15))))
  ]));
}

class OwnerForm extends StatefulWidget {
  final Map<String, dynamic>? item; const OwnerForm({Key? key, this.item}) : super(key: key);
  @override _OwnerFormState createState() => _OwnerFormState();
}
class _OwnerFormState extends State<OwnerForm> {
  final _n = TextEditingController(), _p = TextEditingController(), _rm = TextEditingController();
  @override void initState() { super.initState(); if(widget.item!=null){ _n.text=widget.item!['name']??''; _p.text=widget.item!['phone']??''; _rm.text=widget.item!['remark']??'';} }
  _save() async {
    if (_n.text.isEmpty) return;
    Map<String, dynamic> d = {'name': _n.text, 'phone': _p.text, 'remark': _rm.text};
    widget.item == null ? await DBHelper.instance.insert('owners', d) : await DBHelper.instance.update('owners', d, widget.item!['id']);
    Navigator.pop(context, true);
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Owner Form')), body: ListView(padding: const EdgeInsets.all(12), children: [
    TextField(controller: _n, decoration: const InputDecoration(labelText: 'Name*', border: OutlineInputBorder
