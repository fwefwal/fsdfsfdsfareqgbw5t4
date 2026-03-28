import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Загружаем .env
  try {
    await dotenv.load(fileName: '../assets/app.env');
    print("✅ app.env успешно загружен!");
    print("API_URL = ${dotenv.env['API_URL']}");
  } catch (e) {
    print("❌ Ошибка загрузки app.env: $e");
  }

  runApp(const MyApp());
}

// ====================== МОДЕЛИ ======================
class AppUser {
  String login;
  String name;
  String surname;
  String email;

  AppUser({
    required this.login,
    this.name = '',
    this.surname = '',
    this.email = '',
  });

  String get fullName => [name, surname].where((e) => e.isNotEmpty).join(' ').trim();
  String get displayName => fullName.isNotEmpty ? fullName : login;

  Map<String, dynamic> toJson() => {
        'login': login,
        'name': name,
        'surname': surname,
        'email': email,
      };

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        login: json['login'] as String,
        name: json['name'] as String? ?? '',
        surname: json['surname'] as String? ?? '',
        email: json['email'] as String? ?? '',
      );
}

final currentUserNotifier = ValueNotifier<AppUser?>(null);
final allUsersNotifier = ValueNotifier<List<AppUser>>([]);

Future<void> loadData() async {
  final prefs = await SharedPreferences.getInstance();
  final currentJson = prefs.getString('current_user');
  if (currentJson != null) {
    currentUserNotifier.value = AppUser.fromJson(jsonDecode(currentJson));
  }

  final usersJson = prefs.getString('all_users');
  if (usersJson != null) {
    allUsersNotifier.value = (jsonDecode(usersJson) as List)
        .map((e) => AppUser.fromJson(e))
        .toList();
  }
}

Future<void> saveCurrentUser(AppUser user) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('current_user', jsonEncode(user.toJson()));

  var list = List<AppUser>.from(allUsersNotifier.value);
  final index = list.indexWhere((u) => u.login == user.login);
  if (index >= 0) {
    list[index] = user;
  } else {
    list.add(user);
  }
  allUsersNotifier.value = list;

  await prefs.setString('all_users', jsonEncode(list.map((u) => u.toJson()).toList()));
}

Future<void> logout() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('current_user');
  currentUserNotifier.value = null;
}

// ====================== КУРС ВАЛЮТ ======================
class CurrencyRate {
  final String currency;
  final double rate;

  CurrencyRate(this.currency, this.rate);
}

class CurrencyService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  Future<List<CurrencyRate>> getRates({String base = 'RUB'}) async {
    // Принудительная загрузка .env на случай hot restart
    if (!dotenv.isInitialized) {
      await dotenv.load(fileName: "assets/app.env");
    }

    final apiUrl = dotenv.env['API_URL'] ?? 'https://v6.exchangerate-api.com/v6/';
    final apiKey = dotenv.env['CURRENCY_API_KEY'];

    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('CURRENCY_API_KEY не найден в .env');
    }

    final url = '${apiUrl}$apiKey/latest/$base';

    try {
      final response = await _dio.get(url);
      final data = response.data;

      if (data['result'] != 'success') {
        throw Exception('API вернул ошибку: ${data['error-type']}');
      }

      final ratesMap = data['conversion_rates'] as Map<String, dynamic>;
      final List<CurrencyRate> rates = [];

      ratesMap.forEach((currency, rate) {
        rates.add(CurrencyRate(currency, (rate as num).toDouble()));
      });

      // Сортируем по коду валюты
      rates.sort((a, b) => a.currency.compareTo(b.currency));
      return rates;
    } catch (e) {
      throw Exception('Ошибка загрузки курсов: $e');
    }
  }
}

class CurrencyScreen extends StatefulWidget {
  const CurrencyScreen({super.key});

  @override
  State<CurrencyScreen> createState() => _CurrencyScreenState();
}

class _CurrencyScreenState extends State<CurrencyScreen> {
  final CurrencyService _service = CurrencyService();
  List<CurrencyRate> _rates = [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadRates();
  }

  Future<void> _loadRates() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final rates = await _service.getRates(base: 'RUB'); // ← можно поменять на USD, EUR и т.д.
      setState(() {
        _rates = rates;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Курс валют'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRates,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(child: Text('Ошибка: $_error', textAlign: TextAlign.center))
              : RefreshIndicator(
                  onRefresh: _loadRates,
                  child: ListView.builder(
                    itemCount: _rates.length,
                    itemBuilder: (context, index) {
                      final rate = _rates[index];
                      return ListTile(
                        title: Text(rate.currency),
                        trailing: Text(
                          rate.rate.toStringAsFixed(4),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// ====================== ОСНОВНОЕ ПРИЛОЖЕНИЕ ======================
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'КТ5 — Пользователи + Курс валют',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const AuthCheck(),
    );
  }
}

class AuthCheck extends StatefulWidget {
  const AuthCheck({super.key});

  @override
  State<AuthCheck> createState() => _AuthCheckState();
}

class _AuthCheckState extends State<AuthCheck> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await loadData();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return ValueListenableBuilder<AppUser?>(
      valueListenable: currentUserNotifier,
      builder: (context, currentUser, child) {
        return currentUser != null ? const HomeNavigator() : const LoginScreen();
      },
    );
  }
}

// LoginScreen, HomeNavigator, UsersListScreen, MyProfileScreen — оставляю как было раньше
// (только третья вкладка теперь CurrencyScreen)

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _loginCtrl = TextEditingController();

  Future<void> _signIn() async {
    final login = _loginCtrl.text.trim();
    if (login.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите логин')));
      return;
    }

    final existing = allUsersNotifier.value.firstWhere(
      (u) => u.login == login,
      orElse: () => AppUser(login: login),
    );

    currentUserNotifier.value = existing;
    await saveCurrentUser(existing);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Добро пожаловать, ${existing.displayName}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Вход / Регистрация')),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person_add, size: 80, color: Colors.green),
            const SizedBox(height: 40),
            TextField(
              controller: _loginCtrl,
              decoration: const InputDecoration(
                labelText: 'Логин',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.alternate_email),
              ),
              onSubmitted: (_) => _signIn(),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _signIn,
                icon: const Icon(Icons.login),
                label: const Text('Войти / Создать'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeNavigator extends StatefulWidget {
  const HomeNavigator({super.key});

  @override
  State<HomeNavigator> createState() => _HomeNavigatorState();
}

class _HomeNavigatorState extends State<HomeNavigator> {
  int _index = 0;

  final List<Widget> _pages = [
    const UsersListScreen(),
    const MyProfileScreen(),
    const CurrencyScreen(),   // ← теперь курс валют
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.group), label: 'Пользователи'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Мой профиль'),
          BottomNavigationBarItem(icon: Icon(Icons.currency_exchange), label: 'Курс валют'),
        ],
      ),
    );
  }
}

// UsersListScreen и MyProfileScreen — оставь как были у тебя раньше
// (я не дублирую их, чтобы не раздувать код)

class UsersListScreen extends StatelessWidget {
  const UsersListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Все пользователи'),
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () async => await logout())],
      ),
      body: ValueListenableBuilder<List<AppUser>>(
        valueListenable: allUsersNotifier,
        builder: (context, users, _) {
          if (users.isEmpty) return const Center(child: Text('Пока нет пользователей'));
          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (ctx, i) {
              final u = users[i];
              return ListTile(
                leading: CircleAvatar(child: Text(u.displayName.isNotEmpty ? u.displayName[0].toUpperCase() : '?')),
                title: Text(u.displayName),
                subtitle: Text(u.login),
              );
            },
          );
        },
      ),
    );
  }
}

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});
  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  late TextEditingController _name, _surname, _email;

  @override
  void initState() {
    super.initState();
    final u = currentUserNotifier.value!;
    _name = TextEditingController(text: u.name);
    _surname = TextEditingController(text: u.surname);
    _email = TextEditingController(text: u.email);
  }

  @override
  void dispose() {
    _name.dispose();
    _surname.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final current = currentUserNotifier.value!;
    final updated = AppUser(
      login: current.login,
      name: _name.text.trim(),
      surname: _surname.text.trim(),
      email: _email.text.trim(),
    );
    currentUserNotifier.value = updated;
    await saveCurrentUser(updated);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Профиль обновлён')));
  }

  @override
  Widget build(BuildContext context) {
    final user = currentUserNotifier.value!;
    return Scaffold(
      appBar: AppBar(title: const Text('Мой профиль')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: CircleAvatar(radius: 50, child: Text(user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : user.login[0].toUpperCase(), style: const TextStyle(fontSize: 48)))),
            const SizedBox(height: 16),
            Center(child: Text(user.displayName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
            Center(child: Text(user.login, style: const TextStyle(color: Colors.grey))),
            const SizedBox(height: 40),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Имя', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _surname, decoration: const InputDecoration(labelText: 'Фамилия', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()), keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 40),
            ElevatedButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Сохранить изменения'), style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52))),
          ],
        ),
      ),
    );
  }
}