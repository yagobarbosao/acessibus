import 'package:flutter/material.dart';

class SelecionarLinhaPage extends StatelessWidget {
  const SelecionarLinhaPage({super.key});

  @override
  Widget build(BuildContext context) {
    final TextEditingController linhaController = TextEditingController();

    return Scaffold(
      backgroundColor: const Color(0xFFF5EEEE),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SizedBox(height: 80),

            // Título
            const Text(
              "Selecionar Linha",
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),

            const SizedBox(height: 20),

            // Campo de texto
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: TextField(
                controller: linhaController,
                decoration: InputDecoration(
                  hintText: "Digite ou escolha a linha",
                  hintStyle: const TextStyle(color: Colors.grey),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.green, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.green, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Botão Confirmar
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {
                // Aqui você pode colocar a lógica depois
                print("Linha escolhida: ${linhaController.text}");
              },
              child: const Text(
                "Confirmar",
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),

            const Spacer(),

            // Logo + texto
            Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    "assets/logo.png",
                    height: 50,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    "ACESSIBUS",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
