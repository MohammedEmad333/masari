import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodle_reminder/screens/masari_library_material_tile.dart';
import 'package:moodle_reminder/services/local_course_library.dart';
import 'package:moodle_reminder/services/local_course_search.dart';
import 'package:moodle_reminder/theme/masari_theme.dart';

void main() {
  const file = CourseMaterial(
    id: 'file',
    title: 'Lecture PDF',
    value: '/saved/lecture.pdf',
    isLink: false,
  );
  const link = CourseMaterial(
    id: 'link',
    title: 'Course website',
    value: 'https://example.org',
    isLink: true,
  );

  test('chapter counts distinguish local files and links', () {
    const chapter = CourseChapter(
      id: 'chapter',
      name: 'Week 1',
      materials: [file, link],
    );
    expect(localChapterFileCount(chapter), 1);
    expect(localChapterLinkCount(chapter), 1);
    expect(localChapterFileCount(const CourseChapter(id: 'empty', name: 'Empty')), 0);
    expect(localChapterLinkCount(const CourseChapter(id: 'empty', name: 'Empty')), 0);
  });

  for (final arabic in [false, true]) {
    testWidgets('material tile preserves open and delete actions in RTL/LTR', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var opened = 0;
      var deleted = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: MasariTheme.light,
          home: Directionality(
            textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
            child: Scaffold(
              body: MasariLibraryMaterialTile(
                material: link,
                arabic: arabic,
                onOpen: () => opened++,
                onDelete: () => deleted++,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Course website'), findsOneWidget);
      expect(find.text(arabic ? 'رابط' : 'Link'), findsOneWidget);
      await tester.tap(find.text('Course website'));
      expect(opened, 1);
      await tester.tap(find.byTooltip(arabic ? 'حذف المادة' : 'Delete material'));
      expect(deleted, 1);
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('file tile renders file type without opening it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MasariLibraryMaterialTile(
            material: file,
            arabic: false,
            onOpen: () {},
            onDelete: () {},
          ),
        ),
      ),
    );
    expect(find.text('File'), findsOneWidget);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
  });
}
