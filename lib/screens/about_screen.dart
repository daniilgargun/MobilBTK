/*
 * Copyright (c) 2024 Daniil Gargun. All rights reserved.
 * Author: Daniil Gargun | Telegram: @Daniilgargun | Email: daniilgorgun38@gmail.com
 */

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/developer_ads_widget.dart';

/// Экран «О приложении»: версия, авторы, ссылки и поддержка.
///
/// Раньше это были разрозненные строки в конце настроек, причём имя
/// разработчика открывало диалог ради одной ссылки, а строка «Художник»
/// выглядела нажимаемой, но не делала ничего.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  static const String _cookieCountKey = 'cookie_count';

  String _version = '';
  int _cookieCount = 0;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadCookieCount();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = '${info.version} (${info.buildNumber})';
      });
    } catch (e) {
      debugPrint('Не удалось получить версию приложения: $e');
    }
  }

  Future<void> _loadCookieCount() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _cookieCount = prefs.getInt(_cookieCountKey) ?? 0;
    });
  }

  /// Открывает ссылку, перебирая варианты: для Telegram сначала пробуем
  /// приложение, затем веб-версию. При полной неудаче сообщаем об этом,
  /// а не молчим, как раньше.
  Future<void> _launchUrl(String urlString) async {
    final candidates = <Uri>[];

    if (urlString.startsWith('https://t.me/')) {
      final domain = urlString.split('/').last;
      if (domain.isNotEmpty) {
        candidates.add(Uri.parse('tg://resolve?domain=$domain'));
      }
      candidates.add(Uri.parse(urlString));
    } else {
      candidates.add(Uri.parse(urlString));
    }

    for (final uri in candidates) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return;
        }
      } catch (e) {
        debugPrint('Не удалось открыть $uri: $e');
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть ссылку')),
      );
    }
  }

  Future<void> _showDonationDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          DeveloperAdsWidget(onCookieCountUpdated: _loadCookieCount),
    );
    await _loadCookieCount();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('О приложении')),
      body: ListView(
        children: [
          _buildHeader(theme),
          const Divider(height: 32),

          _sectionTitle(theme, 'Авторы'),
          const ListTile(
            leading: Icon(Icons.code),
            title: Text('Gargun Daniil'),
            subtitle: Text('Разработчик'),
          ),
          const ListTile(
            leading: Icon(Icons.brush_outlined),
            title: Text('Просто Юрик'),
            subtitle: Text('Художник'),
          ),

          const Divider(height: 32),

          _sectionTitle(theme, 'Ссылки'),
          ListTile(
            leading: const Icon(Icons.telegram),
            title: const Text('Telegram разработчика'),
            subtitle: const Text('@Daniilgargun'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _launchUrl('https://t.me/Daniilgargun'),
          ),
          ListTile(
            leading: const Icon(Icons.public),
            title: const Text('Сайт колледжа'),
            subtitle: const Text('bartc.by'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _launchUrl('https://bartc.by'),
          ),
          ListTile(
            leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('Telegram-бот'),
            subtitle: const Text('@BTKraspbot'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _launchUrl('https://t.me/BTKraspbot'),
          ),

          const Divider(height: 32),

          _sectionTitle(theme, 'Поддержка'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Приложение бесплатное. Поддержать можно просмотром '
              'короткого ролика — это ни к чему не обязывает.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _showDonationDialog,
                    icon: const Icon(Icons.cookie_outlined),
                    label: const Text('Поддержать автора'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cookie, size: 18, color: Colors.amber),
                      const SizedBox(width: 6),
                      Text(
                        '$_cookieCount',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.schedule,
              size: 34,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 12),
          Text('БТК Расписание', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            _version.isEmpty ? '—' : _version,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
