import 'package:flutter/material.dart';

// ==============================================================================
// 🔍 SEARCH DESTINATION BAR & RECOMMENDATION CHIPS
// Allows tourists to search places or auto-fill current GPS coordinates.
// ==============================================================================
class SearchDestinationBar extends StatelessWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onGpsTap;
  final ValueChanged<String>? onChipTap;

  const SearchDestinationBar({
    super.key,
    this.controller,
    this.onSubmitted,
    this.onGpsTap,
    this.onChipTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PLAN A SAFE JOURNEY',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: Color(0xFF1A2D4F),
          ),
        ),
        const SizedBox(height: 10),

        // Search Input Bar Container
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A0E4E91),
                blurRadius: 15,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            onSubmitted: onSubmitted,
            decoration: InputDecoration(
              hintText: 'Search destination (e.g. Pykara, Coonoor)...',
              hintStyle: const TextStyle(
                color: Color(0xFF8A99AF),
                fontSize: 14,
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: Color(0xFF087CF0),
                size: 24,
              ),
              suffixIcon: IconButton(
                onPressed: onGpsTap ?? () {},
                icon: const Icon(
                  Icons.my_location_rounded,
                  color: Color(0xFF087CF0),
                  size: 22,
                ),
                tooltip: 'Use current GPS location',
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Quick Destination Chips
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _QuickChip(
              label: '🌲 Ooty Lake',
              onTap: () => onChipTap?.call('Ooty Lake'),
            ),
            _QuickChip(
              label: '⛰️ Doddabetta Peak',
              onTap: () => onChipTap?.call('Doddabetta Peak'),
            ),
            _QuickChip(
              label: '🌊 Pykara Falls',
              onTap: () => onChipTap?.call('Pykara Falls'),
            ),
            _QuickChip(
              label: '🍵 Tea Gardens',
              onTap: () => onChipTap?.call('Tea Gardens Ooty'),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Quick Chip Helper Widget ────────────────────────────────────────────────
class _QuickChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF53647F),
          ),
        ),
      ),
    );
  }
}
