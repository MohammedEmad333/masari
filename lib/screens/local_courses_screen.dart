import 'package:flutter/services.dart';

import '../services/course_share_codec.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/local_course_library.dart';

class LocalCoursesScreen extends StatefulWidget {
  const LocalCoursesScreen({super.key, required this.arabic, this.incomingLink});
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

  Future<void> _shareCourse(LocalCourse course) async {
    try {
      final url = CourseShareCodec.encode(course);
      await Clipboard.setData(ClipboardData(text: url));
      await const MethodChannel('moodle_reminder/course_share').invokeMethod<void>(
        'shareLink',
        {'url': url},
      );
    } catch (_) {
      _error();
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
            decoration: InputDecoration(labelText: t('Paste course link', 'ألصق رابط المساق')),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Cancel', 'إلغاء'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, field.text.trim()), child: Text(t('Preview', 'معاينة'))),
          ],
        ),
      );
      if (url != null && url.isNotEmpty && mounted) await _importSharedCourse(url);
    } finally {
      field.dispose();
    }
  }

  Future<void> _importSharedCourse(String link) async {
    final library = _library;
    if (library == null || !mounted) return;
    try {
      final course = CourseShareCodec.decode(link, library);
      final approved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('Import shared course?', 'استيراد المساق المشارك؟')),
          content: Text(t(
            '${course.name}: ${course.chapters.length} chapters. Only web links will be imported; no local files.',
            '${course.name}: ${course.chapters.length} فصول. سيتم استيراد الروابط فقط دون الملفات المحلية.',
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Cancel', 'إلغاء'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Import', 'استيراد'))),
          ],
        ),
      );
      if (approved == true && mounted) {
        await _commit([..._courses, course]);
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
                          if (value == 'edit') _editCourse(course);
                          if (value == 'delete') _removeCourse(course);
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'share',
                            child: Text(t('Share course', 'مشاركة المساق')),
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
