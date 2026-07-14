import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isShortScreen = screenSize.height < 400;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          const _BackgroundGradients(),
          const _BackgroundSparkles(),
          SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 45,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const _LogoWithGlow(),
                        SizedBox(height: isShortScreen ? 12 : 24),
                        Text(
                          "OkeyX",
                          style: GoogleFonts.poppins(
                            fontSize: isShortScreen ? 32 : 44,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 1.5,
                            shadows: [
                              Shadow(
                                color: const Color(0xFFEAB308).withOpacity(0.35),
                                blurRadius: 15,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                        ).animate().fade(duration: 500.ms).slideY(begin: 0.1, end: 0),
                        SizedBox(height: isShortScreen ? 4 : 8),
                        Text(
                          "Arkadaşlarınla Okey Keyfi",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: isShortScreen ? 13 : 16,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xFF94A3B8),
                            letterSpacing: 0.5,
                          ),
                        ).animate().fade(delay: 200.ms, duration: 500.ms).slideY(begin: 0.1, end: 0),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  flex: 55,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0),
                    alignment: Alignment.center,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _LandscapePremiumButton(
                            text: "Giriş Yap",
                            onPressed: () => context.go('/lobby'),
                          ),
                          SizedBox(height: isShortScreen ? 10 : 16),
                          _LandscapePremiumButton(
                            text: "Kayıt Ol",
                            onPressed: () => context.go('/register'),
                          ),
                          SizedBox(height: isShortScreen ? 10 : 16),
                          _LandscapePremiumButton(
                            text: "Misafir Girişi",
                            isSecondary: true,
                            onPressed: () => context.go('/lobby'),
                          ),
                        ]
                            .animate(interval: 80.ms)
                            .fade(delay: 300.ms, duration: 500.ms)
                            .slideX(begin: 0.1, end: 0, curve: Curves.easeOutQuad),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const _FooterSection(),
        ],
      ),
    );
  }
}

class _BackgroundGradients extends StatelessWidget {
  const _BackgroundGradients();
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.3, -0.1),
                radius: 1.4,
                colors: [Color(0xFF2E150B), Color(0xFF0F172A)],
                stops: [0.0, 1.0],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.5, 0.5),
                radius: 1.5,
                colors: [Color(0xFF1B112D), Colors.transparent],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BackgroundSparkles extends StatelessWidget {
  const _BackgroundSparkles();
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return Stack(
          children: [
            _buildSparkle(top: h * 0.12, left: w * 0.22, size: 6, delay: 0.ms),
            _buildSparkle(top: h * 0.22, left: w * 0.78, size: 8, delay: 400.ms),
            _buildSparkle(top: h * 0.75, left: w * 0.15, size: 5, delay: 800.ms),
            _buildSparkle(top: h * 0.68, left: w * 0.85, size: 7, delay: 1200.ms),
          ],
        );
      },
    );
  }

  Widget _buildSparkle({required double top, required double left, required double size, required Duration delay}) {
    return Positioned(
      top: top,
      left: left,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFFFF3D1).withOpacity(0.8),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE9B646).withOpacity(0.5),
              blurRadius: size * 2.5,
              spreadRadius: size,
            ),
          ],
        ),
      )
          .animate(onPlay: (controller) => controller.repeat(reverse: true))
          .fade(duration: 1800.ms, delay: delay, begin: 0.2, end: 0.8)
          .scale(duration: 1800.ms, delay: delay, begin: const Offset(0.6, 0.6), end: const Offset(1.2, 1.2)),
    );
  }
}

class _LogoWithGlow extends StatelessWidget {
  const _LogoWithGlow();
  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isShort = screenHeight < 400;
    final logoSize = isShort ? 80.0 : 110.0;

    return Container(
      width: logoSize,
      height: logoSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEAB308).withOpacity(0.2),
            blurRadius: 40,
            spreadRadius: 10,
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFFFDE047), Color(0xFFEAB308), Color(0xFFCA8A04)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: const Color(0xFFFEF08A).withOpacity(0.7), width: isShort ? 2.0 : 3.0),
        ),
        child: Center(
          child: Text(
            "OX",
            style: GoogleFonts.poppins(
              fontSize: isShort ? 30 : 42,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF0F172A),
              letterSpacing: 1.5,
            ),
          ),
        ),
      ),
    )
        .animate()
        .scale(duration: 600.ms, curve: Curves.easeOutBack)
        .shimmer(delay: 600.ms, duration: 1200.ms, color: Colors.white30);
  }
}

class _LandscapePremiumButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;
  final bool isSecondary;

  const _LandscapePremiumButton({required this.text, required this.onPressed, this.isSecondary = false});

  @override
  State<_LandscapePremiumButton> createState() => _LandscapePremiumButtonState();
}

class _LandscapePremiumButtonState extends State<_LandscapePremiumButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final gradientColors = widget.isSecondary
        ? const [Color(0xFFEAB308), Color(0xFFCA8A04), Color(0xFF854D0E)]
        : const [Color(0xFFFDE047), Color(0xFFEAB308), Color(0xFFCA8A04)];

    final textColor = widget.isSecondary ? const Color(0xFFFFFFFF) : const Color(0xFF0F172A);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.96 : (_isHovered ? 1.03 : 1.0),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: Container(
            width: double.infinity,
            height: 70,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(35),
              gradient: LinearGradient(colors: gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFCA8A04).withOpacity(_isHovered ? 0.45 : 0.3),
                  blurRadius: _isHovered ? 18 : 10,
                  offset: const Offset(0, 5),
                ),
              ],
              border: Border.all(color: const Color(0xFFFEF08A).withOpacity(widget.isSecondary ? 0.4 : 0.7), width: 1.5),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(35),
                onTap: widget.onPressed,
                hoverColor: Colors.white.withOpacity(0.08),
                splashColor: const Color(0xFF0F172A).withOpacity(0.12),
                highlightColor: Colors.transparent,
                child: Center(
                  child: Text(
                    widget.text,
                    style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.bold, color: textColor, letterSpacing: 0.8),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FooterSection extends StatelessWidget {
  const _FooterSection();
  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 12,
      left: 0,
      right: 0,
      child: Center(
        child: Text(
          "Sürüm 0.0.1",
          style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w400, color: const Color(0xFF64748B), letterSpacing: 1.0),
        ).animate().fade(delay: 600.ms, duration: 600.ms),
      ),
    );
  }
}