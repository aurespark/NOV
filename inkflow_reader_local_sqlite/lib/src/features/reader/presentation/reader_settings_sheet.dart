import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/font_loader_service.dart';
import '../domain/reader_models.dart';
import 'reader_controller.dart';

class ReaderSettingsSheet extends ConsumerStatefulWidget {
  const ReaderSettingsSheet({
    required this.chapters,
    required this.currentOffset,
    required this.onChapterSelected,
    super.key,
  });

  final List<ChapterMarker> chapters;
  final int currentOffset;
  final ValueChanged<ChapterMarker> onChapterSelected;

  @override
  ConsumerState<ReaderSettingsSheet> createState() =>
      _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends ConsumerState<ReaderSettingsSheet> {
  static const _chapterItemExtent = 64.0;
  final ScrollController _chapterController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  @override
  void didUpdateWidget(covariant ReaderSettingsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentOffset != widget.currentOffset ||
        oldWidget.chapters != widget.chapters) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
    }
  }

  @override
  void dispose() {
    _chapterController.dispose();
    super.dispose();
  }

  void _scrollToCurrent() {
    if (!mounted || !_chapterController.hasClients || widget.chapters.isEmpty) {
      return;
    }
    final currentChapter = widget.chapters.lastWhere(
      (chapter) => chapter.offset <= widget.currentOffset,
      orElse: () => widget.chapters.first,
    );
    final index = widget.chapters.indexOf(currentChapter);
    if (index <= 0) {
      _chapterController.jumpTo(0);
      return;
    }
    final target = (index * _chapterItemExtent - 96)
        .clamp(0.0, _chapterController.position.maxScrollExtent);
    _chapterController.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final value = ref.watch(readerSettingsProvider);
    final controller = ref.read(readerSettingsProvider.notifier);
    void set(ReaderSettings v) => controller.update(v);
    final chapters = widget.chapters;
    final currentChapter = chapters.lastWhere(
      (chapter) => chapter.offset <= widget.currentOffset,
      orElse: () => chapters.first,
    );

    final isDark = ThemeData.estimateBrightnessForColor(value.backgroundColor) ==
        Brightness.dark;

    final sheetTheme = Theme.of(context).copyWith(
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: value.backgroundColor,
      canvasColor: value.backgroundColor,
      cardColor: value.backgroundColor,
      primaryColor: value.textColor,
      colorScheme: (isDark ? const ColorScheme.dark() : const ColorScheme.light())
          .copyWith(
        primary: value.textColor,
        onPrimary: value.backgroundColor,
        surface: value.backgroundColor,
        onSurface: value.textColor,
      ),
      textTheme: Theme.of(context).textTheme.apply(
            bodyColor: value.textColor,
            displayColor: value.textColor,
          ),
      iconTheme: IconThemeData(color: value.textColor.withAlpha((0.85 * 255).round())),
      sliderTheme: Theme.of(context).sliderTheme.copyWith(
        activeTrackColor: value.textColor.withAlpha((0.7 * 255).round()),
        inactiveTrackColor: value.textColor.withAlpha((0.3 * 255).round()),
        thumbColor: value.textColor,
        overlayColor: value.textColor.withAlpha((0.2 * 255).round()),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: value.textColor,
        unselectedLabelColor:
            value.textColor.withAlpha((0.75 * 255).round()),
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(
            color: value.textColor,
            width: 2,
          ),
        ),
        indicatorColor: value.textColor,
        dividerColor: value.textColor.withAlpha((0.2 * 255).round()),
      ),
      listTileTheme: Theme.of(context).listTileTheme.copyWith(
            selectedTileColor: value.textColor.withAlpha((0.12 * 255).round()),
            iconColor: value.textColor.withAlpha((0.85 * 255).round()),
            textColor: value.textColor,
            selectedColor: value.textColor,
          ),
      dividerTheme: DividerThemeData(
        color: value.textColor.withAlpha((0.2 * 255).round()),
        space: 30,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: value.textColor),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: value.textColor.withAlpha((0.1 * 255).round()),
          foregroundColor: value.textColor,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return value.textColor;
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return value.textColor.withAlpha((0.5 * 255).round());
          }
          return null;
        }),
      ),
    );

    final chapterPanel = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
          child: Text(
            '章節',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: value.textColor),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _chapterController,
            itemExtent: _chapterItemExtent,
            itemCount: chapters.length,
            itemBuilder: (_, index) {
              final chapter = chapters[index];
              final selected = chapter.offset == currentChapter.offset;
              return Material(
                color: Colors.transparent,
                child: ListTile(
                  dense: true,
                  selected: selected,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  title: Text(
                    chapter.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onChapterSelected(chapter);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
    final settingsPanel = SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '閱讀設定',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: value.textColor),
          ),
          const SizedBox(height: 12),
          _slider(
            '字體大小',
            value.fontSize,
            14,
            34,
            (v) => set(value.copyWith(fontSize: v)),
            value.textColor,
          ),
          _slider(
            '行距',
            value.lineHeight,
            1.2,
            2.2,
            (v) => set(value.copyWith(lineHeight: v)),
            value.textColor,
          ),
          _slider(
            '字距',
            value.letterSpacing,
            0,
            2,
            (v) => set(value.copyWith(letterSpacing: v)),
            value.textColor,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 10,
            children: [
              for (final theme in const [
                (Color(0xfff4ecd8), Color(0xff3b332b)), // sepia
                (Color(0xffffffff), Color(0xff202020)), // white
                (Color(0xffdce8d5), Color(0xff26352a)), // green
                (Color(0xff121212), Color(0xffd6d6d6)), // dark
              ])
                InkWell(
                  onTap: () => set(
                    value.copyWith(
                      backgroundColor: theme.$1,
                      textColor: theme.$2,
                    ),
                  ),
                  borderRadius: BorderRadius.circular(30),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: theme.$1,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: value.backgroundColor == theme.$1
                            ? (isDark
                                ? const Color(0xffd1b399)
                                : const Color(0xff755842))
                            : value.textColor.withAlpha((0.2 * 255).round()),
                        width: 2.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, box) {
              final importButton = FilledButton.tonalIcon(
                onPressed: () async {
                  final picked = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: const ['ttf'],
                  );
                  final path = picked?.files.single.path;
                  if (path == null || !context.mounted) return;
                  try {
                    final loaded =
                        await FontLoaderService().importAndLoad(path);
                    await controller.update(
                      value.copyWith(
                        fontFamily: loaded.family,
                        fontPath: loaded.path,
                        fontName: loaded.name,
                      ),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已套用字體：${loaded.name}')),
                      );
                    }
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('字體匯入失敗，請確認檔案為有效的 TTF'),
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('匯入字體'),
              );
              if (box.maxWidth < 330) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.font_download_outlined),
                      title: Text(value.fontName ?? '系統預設字體'),
                      subtitle: const Text('僅支援 TTF'),
                    ),
                    importButton,
                  ],
                );
              }
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.font_download_outlined),
                title: Text(
                  value.fontName ?? '系統預設字體',
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: const Text('僅支援 TTF'),
                trailing: importButton,
              );
            },
          ),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('點擊左右兩側翻頁'),
            subtitle: const Text('關閉後仍可左右滑動'),
            value: value.tapPageTurnEnabled,
            onChanged: (v) => set(value.copyWith(tapPageTurnEnabled: v)),
          ),
        ],
      ),
    );
    return Theme(
      data: sheetTheme,
      child: Material(
        color: value.backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              14 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: value.textColor.withAlpha((0.2 * 255).round()),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      if (box.maxWidth < 600) {
                        return DefaultTabController(
                          length: 2,
                          child: Column(
                            children: [
                              const TabBar(
                                tabs: [
                                  Tab(text: '章節'),
                                  Tab(text: '閱讀設定'),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: TabBarView(
                                  children: [chapterPanel, settingsPanel],
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 150, child: chapterPanel),
                          const VerticalDivider(width: 24),
                          Expanded(child: settingsPanel),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _slider(
    String name,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
    Color textColor,
  ) =>
      Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(name, style: TextStyle(color: textColor)),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              value.toStringAsFixed(1),
              style: TextStyle(color: textColor.withAlpha((0.8 * 255).round())),
            ),
          ),
        ],
      );
}

