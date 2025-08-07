// main.dart
import 'package:flutter/material.dart';
import 'chat_screen.dart'; // Or the correct path to your chat_screen.dart

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gemma App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const MyChatScreen(), // Make sure 'ChatScreen' is recognized here
    );
  }
}