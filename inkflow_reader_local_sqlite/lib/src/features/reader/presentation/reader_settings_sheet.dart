import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/font_loader_service.dart';
import '../domain/reader_models.dart';
import 'reader_controller.dart';

class ReaderSettingsSheet extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(readerSettingsProvider);
    final controller = ref.read(readerSettingsProvider.notifier);
    void set(ReaderSettings v) => controller.update(v);
    final currentChapter = chapters.lastWhere(
      (chapter) => chapter.offset <= currentOffset,
      orElse: () => chapters.first,
    );
    final chapterPanel = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(8, 0, 8, 10),
          child: Text(
            '章節',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: chapters.length,
            itemBuilder: (_, index) {
              final chapter = chapters[index];
              final selected = chapter.offset == currentChapter.offset;
              return ListTile(
                dense: true,
                selected: selected,
                selectedTileColor: const Color(0xffeadfd3),
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
                  onChapterSelected(chapter);
                },
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
          const Text(
            '閱讀設定',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _slider(
            '字體大小',
            value.fontSize,
            14,
            34,
            (v) => set(value.copyWith(fontSize: v)),
          ),
          _slider(
            '行距',
            value.lineHeight,
            1.2,
            2.2,
            (v) => set(value.copyWith(lineHeight: v)),
          ),
          _slider(
            '字距',
            value.letterSpacing,
            0,
            2,
            (v) => set(value.copyWith(letterSpacing: v)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 10,
            children: [
              for (final theme in const [
                (Color(0xfff4ecd8), Color(0xff3b332b)),
                (Color(0xffffffff), Color(0xff202020)),
                (Color(0xffdce8d5), Color(0xff26352a)),
                (Color(0xff121212), Color(0xffd6d6d6)),
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
                            ? const Color(0xff755842)
                            : Colors.black12,
                        width: 2,
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
                    final loaded = await FontLoaderService().importAndLoad(path);
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
          const Divider(height: 30),
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
    return Container(
      height: MediaQuery.sizeOf(context).height * .72,
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        14 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xfffbf8f1),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
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
    );
  }

  Widget _slider(
    String name,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) => Row(
    children: [
      SizedBox(width: 74, child: Text(name)),
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ),
      SizedBox(width: 40, child: Text(value.toStringAsFixed(1))),
    ],
  );
}
