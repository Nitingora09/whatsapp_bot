import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'license_service.dart';

class SponsoredAd {
  final String id;
  final String badge;
  final String title;
  final String subtitle;
  final String description;
  final String ctaText;
  final String targetUrl;
  final IconData icon;
  final List<Color> gradientColors;

  const SponsoredAd({
    required this.id,
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.ctaText,
    required this.targetUrl,
    required this.icon,
    required this.gradientColors,
  });
}

class AdService {
  static int _currentAdIndex = 0;

  static const List<SponsoredAd> sponsorAds = [
    SponsoredAd(
      id: 'ad_b2b_leads',
      badge: 'SPONSORED PARTNER ⚡',
      title: 'B2B Business Leads & Data Extractor',
      subtitle: 'Extract 50,000+ verified direct client numbers from Google Maps & Web',
      description:
          'Get fresh, targeted local business leads categorized by city and niche. Perfect for high-speed WhatsApp marketing.',
      ctaText: 'Explore Leads Pack (50% Off)',
      targetUrl: 'https://wa.me/919610993628?text=Hello!%20I%20want%20details%20about%20B2B%20Leads%20Extractor',
      icon: Icons.travel_explore_rounded,
      gradientColors: [Color(0xFF1E3A8A), Color(0xFF2563EB), Color(0xFF38BDF8)],
    ),
    SponsoredAd(
      id: 'ad_marketing_suite',
      badge: 'FEATURED TOOL 🔥',
      title: 'AI Auto-Responder & Chatbot Pro',
      subtitle: 'Automatically reply to customer inquiries 24/7 with ChatGPT intelligence',
      description:
          'Never lose a lead again. Connect AI auto-reply bot to your WhatsApp account for instantaneous sales closing.',
      ctaText: 'Get AI Bot Access',
      targetUrl: 'https://wa.me/919610993628?text=Hello!%20Tell%20me%20about%20AI%20Chatbot%20Pro',
      icon: Icons.smart_toy_rounded,
      gradientColors: [Color(0xFF4C1D95), Color(0xFF7C3AED), Color(0xFFA855F7)],
    ),
    SponsoredAd(
      id: 'ad_bulk_sms',
      badge: 'TRENDING SOLUTION ⭐',
      title: 'Pan-India Fast SMS & OTP Gateway',
      subtitle: 'Deliver bulk SMS to DND numbers with 99.9% uptime delivery report',
      description:
          'Backup gateway for high-priority business alerts, transaction updates, and offline client outreach.',
      ctaText: 'Claim Free SMS Credits',
      targetUrl: 'https://wa.me/919610993628?text=Hello!%20Interested%20in%20Bulk%20SMS%20Gateway',
      icon: Icons.send_and_archive_rounded,
      gradientColors: [Color(0xFF064E3B), Color(0xFF059669), Color(0xFF34D399)],
    ),
  ];

  static SponsoredAd get nextAd {
    final ad = sponsorAds[_currentAdIndex % sponsorAds.length];
    _currentAdIndex++;
    return ad;
  }

  /// Show Ad before sending messages (Triggered on click)
  static Future<bool> showPreSendAd(BuildContext context, {VoidCallback? onUpgradePro}) async {
    // Pro licensed users bypass all ads
    if (LicenseService.isLicensed) return true;

    final ad = nextAd;
    return await _showAdDialog(
      context: context,
      ad: ad,
      isPreSend: true,
      onUpgradePro: onUpgradePro,
    );
  }

  /// Show Ad immediately after message broadcast completes
  static Future<void> showPostSendAd(BuildContext context, {VoidCallback? onUpgradePro}) async {
    // Pro licensed users bypass all ads
    if (LicenseService.isLicensed) return;

    final ad = nextAd;
    await _showAdDialog(
      context: context,
      ad: ad,
      isPreSend: false,
      onUpgradePro: onUpgradePro,
    );
  }

  static Future<bool> _showAdDialog({
    required BuildContext context,
    required SponsoredAd ad,
    required bool isPreSend,
    VoidCallback? onUpgradePro,
  }) async {
    int countdown = isPreSend ? 3 : 2;
    Timer? timer;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          timer ??= Timer.periodic(const Duration(seconds: 1), (t) {
            if (countdown > 0) {
              setDialogState(() {
                countdown--;
              });
            } else {
              t.cancel();
            }
          });

          return AlertDialog(
            backgroundColor: const Color(0xFF0F172A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: ad.gradientColors[1].withValues(alpha: 0.6),
                width: 1.5,
              ),
            ),
            titlePadding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            actionsPadding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        ad.badge,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isPreSend ? 'Sponsor Ad' : 'Broadcast Finished',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (countdown > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Skip in ${countdown}s',
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  )
                else
                  InkWell(
                    onTap: () {
                      timer?.cancel();
                      Navigator.pop(ctx, true);
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Text('Skip', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                          SizedBox(width: 2),
                          Icon(Icons.close, size: 12, color: Colors.white),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Ad Banner Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: ad.gradientColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: ad.gradientColors[1].withValues(alpha: 0.4),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(ad.icon, color: Colors.white, size: 26),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ad.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: List.generate(
                                    5,
                                    (i) => const Icon(Icons.star, color: Color(0xFFFFD700), size: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        ad.subtitle,
                        style: const TextStyle(
                          color: Color(0xFFF1F5F9),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        ad.description,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // CTA Button (Open Sponsor Link)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    final uri = Uri.parse(ad.targetUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text(
                    ad.ctaText,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 8),

                // Upgrade to remove ads promo
                Center(
                  child: InkWell(
                    onTap: () {
                      timer?.cancel();
                      Navigator.pop(ctx, false);
                      if (onUpgradePro != null) onUpgradePro();
                    },
                    child: const Text(
                      '👑 Want 100% Ad-Free Experience? Upgrade to Pro (₹49+)',
                      style: TextStyle(
                        color: Color(0xFFF59E0B),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: countdown == 0 ? Colors.white : Colors.white38,
                ),
                onPressed: countdown == 0
                    ? () {
                        timer?.cancel();
                        Navigator.pop(ctx, true);
                      }
                    : null,
                child: Text(
                  isPreSend
                      ? (countdown == 0 ? 'Continue to Send Messages 🚀' : 'Please wait ${countdown}s...')
                      : (countdown == 0 ? 'Close Ad ✕' : 'Please wait ${countdown}s...'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          );
        },
      ),
    );

    timer?.cancel();
    return result ?? true;
  }
}
