import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';

void main() {
  runApp(const TravelRiskApp());
}

class TravelRiskApp extends StatelessWidget {
  const TravelRiskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tour Guard',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const SplashScreen(),
    );
  }
}

// import 'package:flutter/material.dart';

// import 'screens/splash_screen.dart';

// // import 'screens/login_screen.dart';

// void main() {
//   runApp(const TravelRiskApp());
// }

// class TravelRiskApp extends StatelessWidget {
//   const TravelRiskApp({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       debugShowCheckedModeBanner: false,
//       title: 'Travel Risk',
//       theme: ThemeData(
//         useMaterial3: true,
//         colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
//       ),
//       home: const SplashScreen(),
//     );
//   }
// }

// class HomeScreen extends StatelessWidget {
//   const HomeScreen({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.grey[100],

//       appBar: AppBar(
//         title: const Text(
//           'Travel Safe',
//           style: TextStyle(fontWeight: FontWeight.bold),
//         ),
//         centerTitle: false,
//       ),

//       body: SafeArea(
//         child: SingleChildScrollView(
//           padding: const EdgeInsets.all(20),

//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               const Text(
//                 'Plan your journey safely',
//                 style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
//               ),

//               const SizedBox(height: 8),

//               Text(
//                 'Check travel risks before you start your trip.',
//                 style: TextStyle(fontSize: 18, color: Colors.grey[700]),
//               ),

//               const SizedBox(height: 25),

//               const Text(
//                 'Where do you want to go?',
//                 style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
//               ),

//               const SizedBox(height: 10),

//               TextField(
//                 decoration: InputDecoration(
//                   hintText: 'Search destination...',
//                   prefixIcon: const Icon(Icons.search),
//                   suffixIcon: IconButton(
//                     icon: const Icon(Icons.my_location),
//                     onPressed: () {},
//                   ),
//                   filled: true,
//                   fillColor: Colors.white,
//                   border: OutlineInputBorder(
//                     borderRadius: BorderRadius.circular(15),
//                     borderSide: BorderSide.none,
//                   ),
//                 ),
//               ),

//               const SizedBox(height: 25),

//               Container(
//                 height: 280,
//                 width: double.infinity,
//                 decoration: BoxDecoration(
//                   color: Colors.blue[50],
//                   borderRadius: BorderRadius.circular(20),
//                   border: Border.all(color: Colors.blue[100]!),
//                 ),
//                 child: const Column(
//                   mainAxisAlignment: MainAxisAlignment.center,
//                   children: [
//                     Icon(Icons.map, size: 70, color: Colors.blue),
//                     SizedBox(height: 15),
//                     Text(
//                       'Map will appear here',
//                       style: TextStyle(
//                         fontSize: 18,
//                         fontWeight: FontWeight.w600,
//                       ),
//                     ),
//                     SizedBox(height: 5),
//                     Text(
//                       'Your route and risk areas will be shown here.',
//                       textAlign: TextAlign.center,
//                     ),
//                   ],
//                 ),
//               ),

//               const SizedBox(height: 25),

//               SizedBox(
//                 width: double.infinity,
//                 height: 55,
//                 child: ElevatedButton.icon(
//                   onPressed: () {},
//                   icon: const Icon(Icons.navigation),
//                   label: const Text(
//                     'START TRIP',
//                     style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
//                   ),
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: Colors.green,

//                     shape: RoundedRectangleBorder(
//                       borderRadius: BorderRadius.circular(15),
//                     ),
//                   ),
//                 ),
//               ),

//               const SizedBox(height: 15),

//               SizedBox(
//                 width: double.infinity,
//                 height: 55,
//                 child: ElevatedButton.icon(
//                   onPressed: () {},
//                   icon: const Icon(Icons.emergency),
//                   label: const Text(
//                     'SOS EMERGENCY',
//                     style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
//                   ),
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: Colors.red,
//                     foregroundColor: Colors.white,
//                     shape: RoundedRectangleBorder(
//                       borderRadius: BorderRadius.circular(15),
//                     ),
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }
