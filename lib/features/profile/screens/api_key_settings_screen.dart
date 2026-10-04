import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/theme/app_palette.dart';
import '../../../shared/widgets/app_widgets.dart';

/// API Key Settings Screen
/// Allows users to input their own Gemini API key for topic/flashcard generation
class ApiKeySettingsScreen extends ConsumerStatefulWidget {
  const ApiKeySettingsScreen({super.key});

  @override
  ConsumerState<ApiKeySettingsScreen> createState() =>
      _ApiKeySettingsScreenState();
}

class _ApiKeySettingsScreenState extends ConsumerState<ApiKeySettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiKeyController = TextEditingController();
  final _storage = const FlutterSecureStorage();

  bool _isLoading = true;
  bool _obscureKey = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    try {
      final key = await _storage.read(key: 'gemini_api_key');
      if (key != null) {
        _apiKeyController.text = key;
      }
    } catch (e) {
      debugPrint('Error loading API key: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveApiKey() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      await _storage.write(
        key: 'gemini_api_key',
        value: _apiKeyController.text.trim(),
      );

      if (mounted) {
        final p = context.palette;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: p.success),
                const SizedBox(width: 12),
                const Text('API key saved successfully!'),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final p = context.palette;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline_rounded, color: p.danger),
                const SizedBox(width: 12),
                Expanded(child: Text('Failed to save API key: $e')),
              ],
            ),
          ),
        );
      }
    }

    if (mounted) setState(() => _isSaving = false);
  }

  Future<void> _openGeminiStudio() async {
    final uri = Uri.parse('https://aistudio.google.com/apikey');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('API Key Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Info Card
                    AppCard(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: p.accentSoft,
                              borderRadius: BorderRadius.circular(
                                AppRadius.chip,
                              ),
                            ),
                            child: Icon(
                              Icons.key_rounded,
                              color: p.accentText,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Use Your Own API Key',
                                    style: t.titleMedium),
                                const SizedBox(height: 4),
                                Text(
                                  'Add your Gemini API key for unlimited topic and flashcard generation.',
                                  style: t.bodySmall!.copyWith(fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // API Key Input
                    Text('Gemini API Key', style: t.titleSmall),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _apiKeyController,
                      obscureText: _obscureKey,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        color: p.text,
                      ),
                      decoration: InputDecoration(
                        hintText: 'AIza...',
                        hintStyle: TextStyle(
                          fontFamily: 'monospace',
                          color: p.textMuted,
                        ),
                        prefixIcon: const Icon(Icons.vpn_key_rounded),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                _obscureKey
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () {
                                setState(() => _obscureKey = !_obscureKey);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.content_paste),
                              onPressed: () async {
                                final data = await Clipboard.getData(
                                  'text/plain',
                                );
                                if (data?.text != null) {
                                  _apiKeyController.text = data!.text!;
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter your API key';
                        }
                        if (!value.startsWith('AIza')) {
                          return 'Invalid API key format';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    // Get API Key Button
                    OutlinedButton.icon(
                      onPressed: _openGeminiStudio,
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Text(
                        'Get API Key from Google AI Studio',
                        style: t.labelLarge!.copyWith(fontSize: 13),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Save Button
                    AppButton(
                      label: 'Save API Key',
                      onPressed: _saveApiKey,
                      loading: _isSaving,
                    ),

                    const SizedBox(height: 24),

                    // Security Note
                    AppCard(
                      color: p.streakSoft,
                      borderColor: p.streak.withValues(alpha: 0.3),
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.security_rounded,
                            color: p.streak,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Your API key is stored securely on your device and never shared.',
                              style: t.bodySmall!.copyWith(color: p.streak),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
