import 'package:flutter/material.dart';

import '../../domain/models/llm_engine_config.dart';
import '../theme/pocket_squad_theme.dart';

/// Modal bottom sheet allowing the user to switch between:
/// 1. **On-Device Gemma 4 E2B IT (`gemma-4-E2B-it.litertlm`, 2.58 GB)** via LiteRT-LM CPU `mmap`
/// 2. **Local LAN Ollama / LM Studio (`LiteLlm`)** with editable `baseUrl` and `model`.
class EngineModeSheet extends StatefulWidget {
  const EngineModeSheet({
    super.key,
    required this.initialConfig,
    required this.isOnWifi,
    required this.onApply,
  });

  final LlmEngineConfig initialConfig;
  final bool isOnWifi;
  final Future<void> Function(LlmEngineConfig config) onApply;

  static Future<void> show(
    BuildContext context, {
    required LlmEngineConfig initialConfig,
    required bool isOnWifi,
    required Future<void> Function(LlmEngineConfig config) onApply,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PocketSquadTheme.obsidianSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => EngineModeSheet(
        initialConfig: initialConfig,
        isOnWifi: isOnWifi,
        onApply: onApply,
      ),
    );
  }

  @override
  State<EngineModeSheet> createState() => _EngineModeSheetState();
}

class _EngineModeSheetState extends State<EngineModeSheet> {
  late LlmEngineMode _selectedMode;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _modelController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.initialConfig.mode;
    _baseUrlController = TextEditingController(
      text: widget.initialConfig.ollamaBaseUrl,
    );
    _modelController = TextEditingController(
      text: widget.initialConfig.ollamaModel,
    );
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final updated = widget.initialConfig.copyWith(
      mode: _selectedMode,
      ollamaBaseUrl: _baseUrlController.text.trim().isEmpty
          ? LlmEngineConfig.defaultOllamaBaseUrl
          : _baseUrlController.text.trim(),
      ollamaModel: _modelController.text.trim().isEmpty
          ? LlmEngineConfig.defaultOllamaModel
          : _modelController.text.trim(),
    );

    try {
      await widget.onApply(updated);
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                const Icon(
                  Icons.memory_rounded,
                  color: PocketSquadTheme.sunsetAmber,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'LLM Runtime & Engine Mode',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (widget.isOnWifi
                                ? PocketSquadTheme.emeraldAudit
                                : PocketSquadTheme.sunsetAmber)
                            .withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        widget.isOnWifi ? Icons.wifi : Icons.wifi_off,
                        size: 14,
                        color: widget.isOnWifi
                            ? PocketSquadTheme.emeraldAudit
                            : PocketSquadTheme.sunsetAmber,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.isOnWifi ? 'Wi-Fi Active' : 'Offline / Cellular',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: widget.isOnWifi
                              ? PocketSquadTheme.emeraldAudit
                              : PocketSquadTheme.sunsetAmber,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildModeOptionCard(
              theme: theme,
              mode: LlmEngineMode.onDeviceLiteRt,
              title: LlmEngineMode.onDeviceLiteRt.label,
              subtitle: '100% standalone on-device FFI (`gemma-4-E2B-it.litertlm`, 2.58 GB · CPU mmap ~0.8 GB RAM). Shared across all 3 sub-agents.',
              icon: Icons.phone_android_rounded,
              accent: PocketSquadTheme.sunsetAmber,
            ),
            const SizedBox(height: 10),
            _buildModeOptionCard(
              theme: theme,
              mode: LlmEngineMode.lanOllama,
              title: LlmEngineMode.lanOllama.label,
              subtitle: 'OpenAI-compatible local LAN endpoint via `flutter_adk` LiteLlm (`ollama_chat/gemma3:4b`).',
              icon: Icons.router_outlined,
              accent: PocketSquadTheme.tropicalTeal,
            ),
            if (_selectedMode == LlmEngineMode.lanOllama) ...<Widget>[
              const SizedBox(height: 14),
              TextField(
                key: const Key('ollama_base_url_field'),
                controller: _baseUrlController,
                decoration: const InputDecoration(
                  labelText: 'Ollama / LM Studio Base URL',
                  hintText: LlmEngineConfig.defaultOllamaBaseUrl,
                  prefixIcon: Icon(Icons.link_rounded, size: 18),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('ollama_model_field'),
                controller: _modelController,
                decoration: const InputDecoration(
                  labelText: 'LiteLlm Model Identifier',
                  hintText: LlmEngineConfig.defaultOllamaModel,
                  prefixIcon: Icon(Icons.auto_awesome_outlined, size: 18),
                ),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('apply_engine_mode_button'),
                onPressed: _isSaving ? null : _submit,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  _isSaving ? 'Applying Engine...' : 'Apply Engine Mode',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeOptionCard({
    required ThemeData theme,
    required LlmEngineMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
  }) {
    final isSelected = _selectedMode == mode;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _selectedMode = mode),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? accent.withValues(alpha: 0.14)
              : PocketSquadTheme.obsidianElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? accent : PocketSquadTheme.obsidianBorder,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? accent : theme.colorScheme.onSurfaceVariant,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(icon, size: 16, color: accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
