import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import '../../../../core/theme/koto_theme.dart';
import '../../domain/models/home_node.dart';
import '../providers/home_providers.dart';
import '../../../canvas/presentation/providers/canvas_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodesAsync = ref.watch(currentHomeNodesProvider);
    final currentFolder = ref.watch(currentFolderIdProvider);
    final folderPath = ref.watch(folderPathProvider);

    return Scaffold(
      body: Row(
        children: [
          // Left Sidebar
          Container(
            width: 232,
            decoration: const BoxDecoration(
              color: KotoTheme.background,
              border: Border(
                right: BorderSide(color: KotoTheme.dividers, width: 1.0),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 48),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Column(
                     crossAxisAlignment: CrossAxisAlignment.start,
                     children: [
                        Text('Scrapyard', style: KotoTextStyles.heading.copyWith(fontSize: 20, letterSpacing: 2.0)),
                        const SizedBox(height: 4),
                        Text('scrap paper', style: KotoTextStyles.caption.copyWith(fontSize: 16, letterSpacing: 2.0)),
                     ],
                  ),
                ),
                const SizedBox(height: 48),
                _SidebarItem(
                  title: 'Home', 
                  isSelected: currentFolder == 'root', 
                  onTap: () {
                     ref.read(currentFolderIdProvider.notifier).state = 'root';
                     ref.read(folderPathProvider.notifier).state = [];
                  }
                ),
                _SidebarItem(
                  title: 'Settings', 
                  isSelected: false, 
                  onTap: () => context.push('/settings')
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                       GestureDetector(
                         onTap: () => ref.read(currentHomeNodesProvider.notifier).createFolder('New Folder'),
                         child: Padding(
                           padding: const EdgeInsets.symmetric(vertical: 8.0),
                           child: Text('+  New folder', style: KotoTextStyles.body.copyWith(color: KotoTheme.accent, fontWeight: FontWeight.w500)),
                         ),
                       ),
                       GestureDetector(
                         onTap: () => ref.read(currentHomeNodesProvider.notifier).createNote('New Note'),
                         child: Padding(
                           padding: const EdgeInsets.symmetric(vertical: 8.0),
                           child: Text('+  New note', style: KotoTextStyles.body.copyWith(color: KotoTheme.accent, fontWeight: FontWeight.w500)),
                         ),
                       ),
                       GestureDetector(
                         onTap: () => ref.read(currentHomeNodesProvider.notifier).importDocument(),
                         child: Padding(
                           padding: const EdgeInsets.symmetric(vertical: 8.0),
                           child: Text('↑  Import app/doc', style: KotoTextStyles.body.copyWith(color: KotoTheme.accent, fontWeight: FontWeight.w500)),
                         ),
                       ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
          
          // Main Content
          Expanded(
            child: Container(
              color: KotoTheme.background,
              padding: const EdgeInsets.all(48.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Breadcrumb Navigation
                  Row(
                    children: [
                       if (currentFolder != 'root') ...[
                          IconButton(
                             icon: const Icon(Icons.arrow_back, color: KotoTheme.primaryText),
                             onPressed: () {
                                final path = ref.read(folderPathProvider);
                                if (path.length > 1) {
                                   ref.read(currentFolderIdProvider.notifier).state = path[path.length - 2].id;
                                   ref.read(folderPathProvider.notifier).state = path.sublist(0, path.length - 1);
                                } else {
                                   ref.read(currentFolderIdProvider.notifier).state = 'root';
                                   ref.read(folderPathProvider.notifier).state = [];
                                }
                             }
                          ),
                          const SizedBox(width: 16),
                       ],
                       Text(
                          currentFolder == 'root' ? 'All Files' : folderPath.last.title, 
                          style: KotoTextStyles.heading.copyWith(fontSize: 24)
                       ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  
                  // Grid View of Nodes
                  Expanded(
                    child: nodesAsync.when(
                      loading: () => const Center(child: CircularProgressIndicator(color: KotoTheme.accent)),
                      error: (err, stack) => Center(child: Text('Error: $err')),
                      data: (nodes) {
                         if (nodes.isEmpty) {
                            return Center(
                               child: Text("Empty folder. Create a note, or import a doc.", style: KotoTextStyles.caption.copyWith(color: KotoTheme.mutedText))
                            );
                         }

                         return GridView.builder(
                           gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                             crossAxisCount: 3,
                             crossAxisSpacing: 32,
                             mainAxisSpacing: 32,
                             childAspectRatio: 1.1,
                           ),
                           itemCount: nodes.length,
                           itemBuilder: (context, index) {
                             final node = nodes[index];
                             return _buildNodeCard(context, ref, node);
                           },
                         );
                      }
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeCard(BuildContext context, WidgetRef ref, HomeNode node) {
     String typeLabel;
    if (node.type == NodeType.folder) typeLabel = '⟨ Pile ⟩';
     else if (node.type == NodeType.document) typeLabel = '⟨ Document ⟩';
    else typeLabel = '⟨ Scrap ⟩';

     return MouseRegion(
       cursor: SystemMouseCursors.click,
       child: GestureDetector(
         onTap: () {
            if (node.type == NodeType.folder) {
               ref.read(currentFolderIdProvider.notifier).state = node.id;
               ref.read(folderPathProvider.notifier).state = [...ref.read(folderPathProvider), node];
            } else if (node.type == NodeType.document) {
               if (node.externalPath != null && node.externalPath!.endsWith('.pdf')) {
                  context.push('/pdf_viewer');
               } else if (node.externalPath != null) {
                  OpenFilex.open(node.externalPath!);
               }
            } else if (node.type == NodeType.note) {
                // Set the active note ID BEFORE navigating so the editor
                // loads this specific note's strokes.
                ref.read(activeNoteIdProvider.notifier).state = node.id;
                openNoteTab(ref, node.id, node.title);
                context.push('/note_editor');
             }
         },
         child: Container(
           decoration: BoxDecoration(
             color: KotoTheme.cardSurface,
             borderRadius: BorderRadius.circular(KotoTheme.borderRadiusDefault),
             boxShadow: const [
                BoxShadow(color: Color(0x05000000), offset: Offset(0, 4), blurRadius: 12)
             ],
           ),
           padding: const EdgeInsets.all(28.0),
           child: Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                     Text(typeLabel, style: KotoTextStyles.label.copyWith(
                        color: node.type == NodeType.folder ? KotoTheme.accent : KotoTheme.mutedText, 
                        letterSpacing: 1.2
                     )),
                     PopupMenuButton<String>(
                        icon: const Icon(Icons.more_horiz, color: KotoTheme.mutedText, size: 20),
                        tooltip: 'Options',
                        elevation: 1,
                        color: KotoTheme.cardSurface,
                        onSelected: (val) {
                          if (val == 'delete') ref.read(currentHomeNodesProvider.notifier).deleteNode(node.id);
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: 'delete', child: Text('Crush', style: TextStyle(color: Colors.redAccent))),
                        ]
                     ),
                  ]
               ),
               const Spacer(),
               Text(
                 node.title,
                 style: KotoTextStyles.heading.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
                 maxLines: 2,
                 overflow: TextOverflow.ellipsis,
               ),
               const SizedBox(height: 8),
               Text(
                 'Updated \${node.updatedAt.month}/\${node.updatedAt.day}',
                 style: KotoTextStyles.caption.copyWith(color: KotoTheme.mutedText),
               ),
             ],
           ),
         ),
       ),
     );
  }
}

class _SidebarItem extends StatelessWidget {
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      hoverColor: Colors.transparent,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 10.0),
        decoration: BoxDecoration(
          color: isSelected ? KotoTheme.accent.withOpacity(0.08) : Colors.transparent,
        ),
        child: Row(
          children: [
             Text(
               title,
               style: KotoTextStyles.body.copyWith(
                 color: isSelected ? KotoTheme.accent : KotoTheme.secondaryText,
                 fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                 letterSpacing: 0.3,
                 fontSize: 15,
               ),
             ),
          ],
        ),
      ),
    );
  }
}
