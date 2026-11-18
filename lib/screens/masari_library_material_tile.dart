import 'package:flutter/material.dart';

import '../services/local_course_library.dart';

/// Presentation-only row. Existing open and delete operations remain owned
/// by LocalCoursesScreen and still require their original confirmations.
class MasariLibraryMaterialTile extends StatelessWidget {
  const MasariLibraryMaterialTile({
    super.key,
    required this.material,
    required this.arabic,
    required this.onOpen,
    required this.onDelete,
  });

  final CourseMaterial material;
  final bool arabic;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final typeLabel = material.isLink
        ? (arabic ? 'رابط' : 'Link')
        : (arabic ? 'ملف' : 'File');

    return ListTile(
      contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 4, 8, 4),
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        child: Icon(
          material.isLink
              ? Icons.link_rounded
              : Icons.insert_drive_file_outlined,
        ),
      ),
      title: Text(material.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(typeLabel),
      onTap: onOpen,
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline_rounded),
        tooltip: arabic ? 'حذف المادة' : 'Delete material',
        onPressed: onDelete,
      ),
    );
  }
}
