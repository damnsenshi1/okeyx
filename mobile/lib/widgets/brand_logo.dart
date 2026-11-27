import 'package:flutter/material.dart';

import '../core/app_theme.dart';

class BrandLogo extends StatelessWidget {
  final double size;
  final bool showName;

  const BrandLogo({super.key, this.size = 72, this.showName = true});

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      'assets/brand/okeyx_logo_transparent.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      cacheWidth: (size * 4).round(),
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: OkeyXColors.deep,
          borderRadius: BorderRadius.circular(size * .22),
          border: Border.all(color: OkeyXColors.cyan.withValues(alpha: .45)),
        ),
        child: Text(
          'OX',
          style: TextStyle(
            color: OkeyXColors.cyan,
            fontWeight: FontWeight.w900,
            fontSize: size * .31,
          ),
        ),
      ),
    );

    if (!showName) return image;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        image,
        SizedBox(width: size * .15),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'OKEYX',
              style: TextStyle(
                color: Colors.white,
                fontSize: size * .34,
                height: .95,
                fontWeight: FontWeight.w900,
                letterSpacing: size * .018,
              ),
            ),
            Text(
              'CANLI 101 OKEY',
              style: TextStyle(
                color: OkeyXColors.gold,
                fontSize: size * .105,
                fontWeight: FontWeight.w900,
                letterSpacing: size * .012,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
