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
    // 1. High-Commission Affiliate (Earns ₹1,500 - ₹2,500 per sale)
    SponsoredAd(
      id: 'ad_hosting_deal',
      badge: 'SPECIAL DEAL ⚡ 75% OFF',
      title: 'Business Website & Free .COM Domain',
      subtitle: 'High-Speed Web Hosting + Free SSL + Free Professional Email',
      description:
          'Get 75% OFF + Free Domain! Perfect for launching your business portfolio, landing page, or online shop. 30-Day Money-Back Guarantee.',
      ctaText: 'Claim 75% Off + Free Domain 🚀',
      targetUrl: 'https://www.hostinger.in/business-web-hosting',
      icon: Icons.language_rounded,
      gradientColors: [Color(0xFF1E1B4B), Color(0xFF4338CA), Color(0xFF6366F1)],
    ),
    // 2. Direct UPI Cash Product (Earns ₹499 directly to user's UPI)
    SponsoredAd(
      id: 'ad_b2b_leads',
      badge: 'HOT SELLER 🔥 50,000+ LEADS',
      title: 'Pan-India Verified Business Leads Pack',
      subtitle: 'Direct WhatsApp Contacts of Shopkeepers, Realtors, Doctors & Dealers',
      description:
          'Never run out of client numbers! Fresh database categorized by city and industry for high-conversion WhatsApp broadcasts.',
      ctaText: 'Get 50,000 Leads on WhatsApp (₹499) 📱',
      targetUrl:
          'https://wa.me/919610993628?text=Hi%20Natish!%20I%20want%20to%20buy%20the%2050000%20Verified%20Business%20Leads%20Pack%20(Rs.499)',
      icon: Icons.groups_rounded,
      gradientColors: [Color(0xFF064E3B), Color(0xFF059669), Color(0xFF10B981)],
    ),
    // 3. In-App Pass Sale (Earns ₹49 / ₹299 / ₹999 directly into user's account)
    SponsoredAd(
      id: 'ad_pro_pass',
      badge: 'GO PRO PASS 👑 AD-FREE',
      title: 'Remove All Ads & Unlock 100x Multi-Round',
      subtitle: 'Lightning-fast zero-wait outreach with priority broadcast queue',
      description:
          'Never wait for countdowns again! Test drive the 24-Hour Pass for only ₹49 or get 30-Day Pro for ₹299.',
      ctaText: '⚡ Remove Ads & Upgrade (₹49) ⚡',
      targetUrl:
          'https://wa.me/919610993628?text=Hello%20Natish!%20I%20want%20to%20upgrade%20to%20Pro%20Ad-Free%20Pass',
      icon: Icons.workspace_premium_rounded,
      gradientColors: [Color(0xFF78350F), Color(0xFFD97706), Color(0xFFF59E0B)],
    ),
    // 4. High-Ticket Agency Deal (Earns ₹4,999 direct client development deal)
    SponsoredAd(
      id: 'ad_ai_chatbot',
      badge: 'AI POWERED 🤖 24/7 CLOSING',
      title: 'Custom AI Chatbot & Auto-Responder Pro',
      subtitle: 'Automatically reply to customer inquiries and close orders on WhatsApp',
      description:
          'Connect ChatGPT intelligence to your WhatsApp business. Never lose a valuable customer inquiry while asleep!',
      ctaText: 'Get Custom AI Bot Setup 💬',
      targetUrl:
          'https://wa.me/919610993628?text=Hi%20Natish!%20Tell%20me%20about%20Custom%20AI%20Chatbot%20Pro%20setup',
      icon: Icons.smart_toy_rounded,
      gradientColors: [Color(0xFF4C1D95), Color(0xFF7C3AED), Color(0xFFA855F7)],
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
                    if (ad.id == 'ad_pro_pass') {
                      timer?.cancel();
                      Navigator.pop(ctx, false);
                      if (onUpgradePro != null) onUpgradePro();
                      return;
                    }
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
