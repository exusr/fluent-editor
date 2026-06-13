import 'package:flutter/material.dart';
import 'package:fluent_editor/localization/fluent_editor_labels.dart';
import 'package:fluent_editor/utils/list_marker_types.dart';

class ListMarkerDialog extends StatefulWidget {
  final String currentMarkerType;
  final Function(String) onMarkerTypeSelected;
  final FluentEditorLabels? labels;

  const ListMarkerDialog({
    super.key,
    required this.currentMarkerType,
    required this.onMarkerTypeSelected,
    this.labels,
  });

  @override
  State<ListMarkerDialog> createState() => _ListMarkerDialogState();
}

class _ListMarkerDialogState extends State<ListMarkerDialog> {
  String _selectedCategory = 'all';

  FluentEditorLabels get _labels => widget.labels ?? const FluentEditorLabels();

  @override
  Widget build(BuildContext context) {
    final markerTypes = _selectedCategory == 'all' 
        ? ListMarkerTypes.allTypes 
        : ListMarkerTypes.getByCategory(_selectedCategory);

    return Dialog(
      child: Container(
        width: 800,
        height: 700,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              _labels.chooseListMarkerType,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),

            // Category tabs
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildCategoryChip('all', _labels.all),
                  _buildCategoryChip('bullet', _labels.bullets),
                  _buildCategoryChip('ordered', _labels.numbers),
                  _buildCategoryChip('checkbox', _labels.checkboxes),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Marker types grid
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: markerTypes.length,
                itemBuilder: (context, index) {
                  final markerType = markerTypes[index];
                  final isSelected = markerType.id == widget.currentMarkerType;

                  return _buildMarkerOption(markerType, isSelected);
                },
              ),
            ),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChip(String category, String label) {
    final isSelected = _selectedCategory == category;
    
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            _selectedCategory = category;
          });
        },
      ),
    );
  }

  Widget _buildMarkerOption(ListMarkerType markerType, bool isSelected) {
    return InkWell(
      onTap: () {
        widget.onMarkerTypeSelected(markerType.id);
        Navigator.of(context).pop();
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSelected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  markerType.icon,
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    markerType.displayName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              markerType.examples.first,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Helper function to show the dialog
Future<void> showListMarkerDialog(
  BuildContext context,
  String currentMarkerType,
  Function(String) onMarkerTypeSelected,
) {
  return showDialog(
    context: context,
    builder: (context) => ListMarkerDialog(
      currentMarkerType: currentMarkerType,
      onMarkerTypeSelected: onMarkerTypeSelected,
    ),
  );
}
