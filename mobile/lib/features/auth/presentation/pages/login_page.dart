import 'package:flutter/material.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.casino,
                color: Colors.amber,
                size: 90,
              ),
              const SizedBox(height: 20),
              const Text(
                "OkeyX",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 50),
              ElevatedButton(
                onPressed: () {},
                child: const Text("Giriş Yap"),
              ),
              const SizedBox(height: 15),
              OutlinedButton(
                onPressed: () {},
                child: const Text("Kayıt Ol"),
              ),
              const SizedBox(height: 15),
              TextButton(
                onPressed: () {},
                child: const Text("Misafir Girişi"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}