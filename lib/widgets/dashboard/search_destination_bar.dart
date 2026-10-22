import 'package:flutter/material.dart';

// ==============================================================================
// 🔍 SEARCH DESTINATION BAR
// Allows tourists to search places or auto-fill current GPS coordinates.
// ==============================================================================
class SearchDestinationBar extends StatelessWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onGpsTap;

  const SearchDestinationBar({
    super.key,
    this.controller,
    this.onSubmitted,
    this.onGpsTap,
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
              hintText: 'Search destination',
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
      ],
    );
  }
}
