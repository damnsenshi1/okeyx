import 'package:flutter/material.dart';
import 'widgets/top_bar.dart';
import 'widgets/player_card.dart';
import 'widgets/quick_play_button.dart';
import 'widgets/bottom_nav.dart';
import 'package:google_fonts/google_fonts.dart';

class LobbyPage extends StatefulWidget {
  const LobbyPage({super.key});

  @override
  State<LobbyPage> createState() => _LobbyPageState();
}

class _LobbyPageState extends State<LobbyPage> {
  int _currentNavIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          // Lobi Tema Arka Planı
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.2,
                  colors: [
                    Color(0xFF2E150B), // Ahşap hissiyatı
                    Color(0xFF0F172A), // Lacivert
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // 1. Üst Bar
                const TopBar(),

                // 2. Orta İçerik Alanı
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Sol Panel - Profil Bilgileri & Hızlı Başla
                        Expanded(
                          flex: 4,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              const PlayerCard(),
                              const SizedBox(height: 16),
                              QuickPlayButton(
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("OkeyX masası aranıyor..."),
                                      backgroundColor: Color(0xFFEAB308),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Sağ Panel - Aktif Masa/Oda Seçimleri
                        Expanded(
                          flex: 6,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B).withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Masa Seçimi",
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: ListView(
                                    physics: const BouncingScrollPhysics(),
                                    children: [
                                      _buildRoomTile("Klasik Okey", "1.000 / 4.000 Coin", "4/4 Oyuncu"),
                                      const SizedBox(height: 8),
                                      _buildRoomTile("Duble & Seri", "5.000 / 20.000 Coin", "2/4 Oyuncu"),
                                      const SizedBox(height: 8),
                                      _buildRoomTile("VIP Masa", "10.000 / 40.000 Coin", "1/4 Oyuncu"),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 3. Alt Navigasyon Barı
                BottomNav(
                  selectedIndex: _currentNavIndex,
                  onItemSelected: (index) {
                    setState(() {
                      _currentNavIndex = index;
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomTile(String name, String rates, String players) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                rates,
                style: GoogleFonts.poppins(
                  color: const Color(0xFF94A3B8),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Text(
                players,
                style: GoogleFonts.poppins(
                  color: const Color(0xFFEAB308),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEAB308),
                  foregroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {},
                child: const Text("Katıl"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}