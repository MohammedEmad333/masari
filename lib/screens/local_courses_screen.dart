import 'dart:io';
import 'package:share_plus/share_plus.dart';
import '../services/course_zip_bundle.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/course_import_merger.dart';
import '../services/course_file_hash_merger.dart';
import '../services/zip_import_change_preview.dart';
import 'package:flutter/services.dart';

import '../services/course_share_codec.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/local_course_library.dart';

class LocalCoursesScreen extends StatefulWidget {
  const LocalCoursesScreen({
    super.key,
    required this.arabic,
    this.incomingLink,
  });
  final bool arabic;
  final String? incomingLink;

  @override
  State<LocalCoursesScreen> createState() => _LocalCoursesScreenState();
}

class _LocalCoursesScreenState extends State<LocalCoursesScreen> {
  LocalCourseLibrary? _library;
  List<LocalCourse> _courses = [];
  bool _busy = true;

  String t(String en, String ar) => widget.arabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final library = await LocalCourseLibrary.open();
      final courses = await library.load();
      if (mounted) {
        setState(() {
          _library = library;
          _courses = courses;
          _busy = false;
        });
        if (widget.incomingLink != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _importSharedCourse(widget.incomingLink!);
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      _error();
    }
  }

  void _error() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          t('Could not save the course library', 'تعذّر حفظ المكتبة الدراسية'),
        ),
      ),
    );
  }

  Future<String?> _askName(String title, [String initial = '']) async {
    final field = TextEditingController(text: initial);
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: field,
            autofocus: true,
            maxLength: 120,
            decoration: InputDecoration(labelText: t('Name', 'الاسم')),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t('Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, field.text.trim()),
              child: Text(t('Save', 'حفظ')),
            ),
          ],
        ),
      );
    } finally {
      field.dispose();
    }
  }

  Future<void> _commit(List<LocalCourse> next) async {
    try {
      await _library!.save(next);
      if (mounted) setState(() => _courses = next);
    } catch (_) {
      _error();
    }
  }

  Future<bool> _confirm() async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('Confirm deletion', 'تأكيد الحذف')),
          content: Text(
            t(
              'This also deletes copied files in this item.',
              'سيتم حذف الملفات المنسوخة داخل هذا العنصر أيضًا.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('Delete', 'حذف')),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _shareZip(LocalCourse course) async {
    try {
      final bundle = await CourseZipBundle.exportCourse(course);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(bundle.path, mimeType: 'application/zip')],
          text: course.name,
        ),
      );
    } catch (_) {
      _error();
    }
  }

  Future<void> _importZip() async {
    try {
      final selected = await FilePicker.pickFiles();
      if (selected.isEmpty || selected.first.path == null) return;
      final path = selected.first.path!;
      if (!path.toLowerCase().endsWith('.zip')) {
        _error();
        return;
      }
      final preview = await CourseZipBundle.previewCourse(File(path));
      final existing = CourseImportMerger.findMatch(
        _courses,
        LocalCourse(id: '', name: preview.name),
      );
      final changes = existing == null
          ? null
          : await ZipImportChangePreview.inspect(File(path), existing);
      if (!mounted) return;
      final approved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            existing == null
                ? t('Import course bundle?', 'استيراد حزمة المساق؟')
                : t('Update existing course?', 'تحديث المساق الموجود؟'),
          ),
          content: Text(
            t(
              '${preview.name} — ${preview.chapters} chapters, ${preview.files} files, ${preview.links} links. ${changes == null ? 'Import as a new course?' : '${changes.newChapters} new chapters, ${changes.newFiles} new files, ${changes.changedFiles} changed file versions, ${changes.duplicateFiles} duplicates skipped, ${changes.newLinks} new links. Existing files stay untouched.'}',
              '${preview.name} — ${preview.chapters} فصول، ${preview.files} ملفات، ${preview.links} روابط. ${changes == null ? 'استيراد كمساق جديد؟' : '${changes.newChapters} فصول جديدة، ${changes.newFiles} ملفات جديدة، ${changes.changedFiles} نسخ ملفات محدّثة، ${changes.duplicateFiles} ملفات مكررة سيتم تخطيها، ${changes.newLinks} روابط جديدة. ستبقى ملفاتك الحالية محفوظة.'}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('Import', 'استيراد')),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
      final imported = await CourseZipBundle.importCourse(
        File(path),
        _library!,
      );
      LocalCourse updated;
      try {
        updated = existing == null
            ? imported
            : await CourseFileHashMerger.merge(existing, imported);
      } catch (_) {
        for (final chapter in imported.chapters) {
          await _library!.deleteChapterFiles(chapter);
        }
        rethrow;
      }
      try {
        final nextCourses = existing == null
            ? [..._courses, updated]
            : [
                for (final item in _courses)
                  if (item.id == existing.id) updated else item,
              ];
        await _library!.save(nextCourses);
        if (mounted) setState(() => _courses = nextCourses);
      } catch (_) {
        for (final chapter in imported.chapters) {
          await _library!.deleteChapterFiles(chapter);
        }
        rethrow;
      }
      if (existing != null) {
        final retained = {
          for (final chapter in updated.chapters)
            for (final resource in chapter.materials) resource.id,
        };
        for (final chapter in imported.chapters) {
          for (final resource in chapter.materials) {
            if (!resource.isLink && !retained.contains(resource.id)) {
              try {
                await _library!.deleteMaterial(resource);
              } catch (_) {
                // Cleanup is best-effort after metadata has been saved.
              }
            }
          }
        }
      }
    } catch (_) {
      _error();
    }
  }

  Future<void> _shareCourse(LocalCourse course) async {
    try {
      final url = CourseShareCodec.encode(course);
      await Clipboard.setData(ClipboardData(text: url));
      await const MethodChannel(
        'moodle_reminder/course_share',
      ).invokeMethod<void>('shareLink', {'url': url});
    } catch (_) {
      _error();
    }
  }

  Future<void> _showCourseQr(LocalCourse course) async {
    try {
      final url = CourseShareCodec.encode(course);
      // QR codes have a much smaller payload capacity than custom share links.
      if (url.length > 2000) {
        throw const FormatException('QR payload too large');
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(t('Course QR code', 'رمز QR للمساق')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(
                data: url,
                version: QrVersions.auto,
                size: 240,
                backgroundColor: Colors.white,
              ),
              const SizedBox(height: 12),
              Text(course.name, textAlign: TextAlign.center),
              Text(
                t(
                  'Scan the QR code and open the course link in Masari.',
                  'امسح رمز QR بالكاميرا وافتح رابط المساق في مساري.',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(t('Close', 'إغلاق')),
            ),
          ],
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'Course is too large for QR. Use Share course instead.',
              'المساق كبير على رمز QR. استخدم مشاركة المساق بدلاً منه.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _pasteSharedCourse() async {
    final field = TextEditingController();
    try {
      final url = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('Import shared course', 'استيراد مساق مشارك')),
          content: TextField(
            controller: field,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: t('Paste course link', 'ألصق رابط المساق'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t('Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, field.text.trim()),
              child: Text(t('Preview', 'معاينة')),
            ),
          ],
        ),
      );
      if (url != null && url.isNotEmpty && mounted) {
        await _importSharedCourse(url);
      }
    } finally {
      field.dispose();
    }
  }

  Future<void> _importSharedCourse(String link) async {
    final library = _library;
    if (library == null || !mounted) return;
    try {
      final course = CourseShareCodec.decode(link, library);
      final linkCount = course.chapters.fold<int>(
        0,
        (total, chapter) => total + chapter.materials.length,
      );
      final approved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('Preview shared course', 'معاينة المساق المشارك')),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(course.name, style: Theme.of(ctx).textTheme.titleLarge),
                Text(
                  t(
                    '${course.chapters.length} chapters • $linkCount links',
                    '${course.chapters.length} فصول • $linkCount روابط',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t(
                    'Only web links are shared. Local files are not included.',
                    'تتضمن المشاركة روابط الويب فقط، ولا تتضمن الملفات المحلية.',
                  ),
                ),
                const Divider(),
                for (final chapter in course.chapters)
                  ExpansionTile(
                    title: Text(chapter.name),
                    subtitle: Text(
                      t(
                        '${chapter.materials.length} links',
                        '${chapter.materials.length} روابط',
                      ),
                    ),
                    children: [
                      for (final material in chapter.materials)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.link),
                          title: Text(material.title),
                          subtitle: Text(
                            material.value,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('Import', 'استيراد')),
            ),
          ],
        ),
      );
      if (approved == true && mounted) {
        final existing = CourseImportMerger.findMatch(_courses, course);
        if (existing == null) {
          await _commit([..._courses, course]);
        } else {
          final update = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(t('Course already exists', 'المساق موجود بالفعل')),
              content: Text(
                t(
                  'Add only missing chapters and links? Your local files and current materials are preserved.',
                  'إضافة الفصول والروابط الناقصة فقط؟ ستبقى ملفاتك المحلية ومحتوياتك الحالية محفوظة.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(t('Cancel', 'إلغاء')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(t('Update', 'تحديث')),
                ),
              ],
            ),
          );
          if (update != true || !mounted) return;
          final merged = CourseImportMerger.merge(existing, course);
          await _commit([
            for (final item in _courses)
              if (item.id == existing.id) merged else item,
          ]);
        }
      }
    } catch (_) {
      _error();
    }
  }

  Future<void> _addCourse() async {
    final name = await _askName(t('New course', 'مساق جديد'));
    if (name == null || name.isEmpty || _library == null) return;
    await _commit([
      ..._courses,
      LocalCourse(id: _library!.newId(), name: name),
    ]);
  }

  Future<void> _editCourse(LocalCourse course) async {
    final name = await _askName(
      t('Rename course', 'تعديل اسم المساق'),
      course.name,
    );
    if (name == null || name.isEmpty) return;
    await _commit([
      for (final c in _courses)
        if (c.id == course.id)
          LocalCourse(id: c.id, name: name, chapters: c.chapters)
        else
          c,
    ]);
  }

  Future<void> _removeCourse(LocalCourse course) async {
    if (!await _confirm()) return;
    try {
      await _commit(_courses.where((c) => c.id != course.id).toList());
      for (final chapter in course.chapters) {
        await _library!.deleteChapterFiles(chapter);
      }
    } catch (_) {
      _error();
    }
  }

  Future<void> _addChapter(LocalCourse course) async {
    final name = await _askName(t('New chapter', 'فصل جديد'));
    if (name == null || name.isEmpty) return;
    await _replaceCourse(course, [
      ...course.chapters,
      CourseChapter(id: _library!.newId(), name: name),
    ]);
  }

  Future<void> _replaceCourse(
    LocalCourse course,
    List<CourseChapter> chapters,
  ) => _commit([
    for (final c in _courses)
      if (c.id == course.id)
        LocalCourse(id: c.id, name: c.name, chapters: chapters)
      else
        c,
  ]);

  Future<void> _replaceChapter(
    LocalCourse course,
    CourseChapter chapter,
    List<CourseMaterial> materials,
  ) => _replaceCourse(course, [
    for (final ch in course.chapters)
      if (ch.id == chapter.id)
        CourseChapter(id: ch.id, name: ch.name, materials: materials)
      else
        ch,
  ]);

  Future<void> _renameChapter(LocalCourse course, CourseChapter chapter) async {
    final name = await _askName(
      t('Rename chapter', 'تعديل اسم الفصل'),
      chapter.name,
    );
    if (name == null || name.isEmpty) return;
    await _replaceCourse(course, [
      for (final ch in course.chapters)
        if (ch.id == chapter.id)
          CourseChapter(id: ch.id, name: name, materials: ch.materials)
        else
          ch,
    ]);
  }

  Future<void> _removeChapter(LocalCourse course, CourseChapter chapter) async {
    if (!await _confirm()) return;
    await _replaceCourse(
      course,
      course.chapters.where((ch) => ch.id != chapter.id).toList(),
    );
    try {
      await _library!.deleteChapterFiles(chapter);
    } catch (_) {
      _error();
    }
  }

  Future<void> _addFiles(LocalCourse course, CourseChapter chapter) async {
    try {
      final result = await FilePicker.pickFiles();
      if (result.isEmpty) return;
      final copied = <CourseMaterial>[];
      try {
        for (final file in result) {
          if (file.path == null) continue;
          copied.add(await _library!.importFile(file.path!, file.name));
        }
        await _replaceChapter(course, chapter, [
          ...chapter.materials,
          ...copied,
        ]);
      } catch (_) {
        for (final item in copied) {
          await _library!.deleteMaterial(item);
        }
        rethrow;
      }
    } catch (_) {
      _error();
    }
  }

  Future<void> _addLink(LocalCourse course, CourseChapter chapter) async {
    final title = await _askName(t('Link title', 'عنوان الرابط'));
    if (title == null || title.isEmpty || !mounted) return;
    final url = await _askName(t('Paste link URL', 'ألصق رابط المادة'));
    if (url == null || url.isEmpty) return;
    try {
      final item = _library!.createLink(title, url);
      await _replaceChapter(course, chapter, [...chapter.materials, item]);
    } catch (_) {
      _error();
    }
  }

  Future<void> _removeMaterial(
    LocalCourse course,
    CourseChapter chapter,
    CourseMaterial item,
  ) async {
    if (!await _confirm()) return;
    await _replaceChapter(
      course,
      chapter,
      chapter.materials.where((m) => m.id != item.id).toList(),
    );
    try {
      await _library!.deleteMaterial(item);
    } catch (_) {
      _error();
    }
  }

  Future<void> _openMaterial(CourseMaterial item) async {
    try {
      if (item.isLink) {
        if (!await launchUrl(
          Uri.parse(item.value),
          mode: LaunchMode.externalApplication,
        )) {
          _error();
        }
      } else {
        final result = await OpenFilex.open(item.value);
        if (result.type != ResultType.done) _error();
      }
    } catch (_) {
      _error();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t('My study library', 'مكتبتي الدراسية')),
        actions: [
          IconButton(
            tooltip: t('Import ZIP bundle', 'استيراد حزمة ZIP'),
            onPressed: _library == null ? null : _importZip,
            icon: const Icon(Icons.folder_zip_outlined),
          ),
          IconButton(
            tooltip: t('Import shared course', 'استيراد مساق مشارك'),
            onPressed: _library == null ? null : _pasteSharedCourse,
            icon: const Icon(Icons.download_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy || _library == null ? null : _addCourse,
        icon: const Icon(Icons.add),
        label: Text(t('Add course', 'إضافة مساق')),
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : _library == null
          ? Center(
              child: Text(
                t('Could not open storage', 'تعذّر فتح مساحة التخزين'),
              ),
            )
          : _courses.isEmpty
          ? Center(child: Text(t('Add your first course', 'أضف مساقك الأول')))
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              children: [
                for (final course in _courses)
                  Card(
                    child: ExpansionTile(
                      key: ValueKey(course.id),
                      leading: const Icon(Icons.menu_book_outlined),
                      title: Text(course.name),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'zip') _shareZip(course);
                          if (value == 'share') _shareCourse(course);
                          if (value == 'qr') _showCourseQr(course);
                          if (value == 'edit') _editCourse(course);
                          if (value == 'delete') _removeCourse(course);
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'zip',
                            child: Text(
                              t('Share as ZIP', 'مشاركة ZIP بالملفات'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'share',
                            child: Text(t('Share course', 'مشاركة المساق')),
                          ),
                          PopupMenuItem(
                            value: 'qr',
                            child: Text(t('Show QR code', 'عرض رمز QR')),
                          ),
                          PopupMenuItem(
                            value: 'edit',
                            child: Text(t('Rename', 'تعديل الاسم')),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text(t('Delete', 'حذف')),
                          ),
                        ],
                      ),
                      children: [
                        for (final chapter in course.chapters)
                          ExpansionTile(
                            key: ValueKey(chapter.id),
                            title: Text(chapter.name),
                            subtitle: Text(
                              t(
                                '${chapter.materials.length} items',
                                '${chapter.materials.length} مادة',
                              ),
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _renameChapter(course, chapter);
                                }
                                if (value == 'delete') {
                                  _removeChapter(course, chapter);
                                }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text(t('Rename', 'تعديل الاسم')),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(t('Delete', 'حذف')),
                                ),
                              ],
                            ),
                            children: [
                              for (final material in chapter.materials)
                                ListTile(
                                  leading: Icon(
                                    material.isLink
                                        ? Icons.link
                                        : Icons.insert_drive_file_outlined,
                                  ),
                                  title: Text(material.title),
                                  onTap: () => _openMaterial(material),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    tooltip: t('Delete', 'حذف'),
                                    onPressed: () => _removeMaterial(
                                      course,
                                      chapter,
                                      material,
                                    ),
                                  ),
                                ),
                              Wrap(
                                spacing: 8,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => _addFiles(course, chapter),
                                    icon: const Icon(
                                      Icons.file_upload_outlined,
                                    ),
                                    label: Text(t('Add files', 'إضافة ملفات')),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _addLink(course, chapter),
                                    icon: const Icon(Icons.add_link),
                                    label: Text(t('Add link', 'إضافة رابط')),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        TextButton.icon(
                          onPressed: () => _addChapter(course),
                          icon: const Icon(Icons.create_new_folder_outlined),
                          label: Text(t('Add chapter', 'إضافة فصل')),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
