import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_patient/core/router/route_names.dart';
import 'package:nubia_patient/presentation/features/auth/widgets/onboarding_slide.dart';

const _slides = [
  OnboardingSlideData(
    icon: Icons.favorite_outline,
    title: 'Bienvenue sur Nubia',
    body: 'Votre espace patient pour suivre vos soins dentaires et rester en contact avec votre cabinet.',
  ),
  OnboardingSlideData(
    icon: Icons.lock_outline,
    title: 'Données de santé sécurisées',
    body: 'Vos données sont chiffrées et hébergées en France, conformément aux exigences HDS.',
  ),
  OnboardingSlideData(
    icon: Icons.notifications_outlined,
    title: 'Restez informé',
    body: 'Recevez des rappels de rendez-vous et les communications importantes de votre cabinet.',
  ),
];

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goToLogin() => context.go(RouteNames.login);

  void _next() {
    if (_currentPage < _slides.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _goToLogin();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLast = _currentPage == _slides.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                key: const Key('onboarding_skip_button'),
                onPressed: _goToLogin,
                child: const Text('Passer'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                key: const Key('onboarding_page_view'),
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (index) =>
                    setState(() => _currentPage = index),
                itemBuilder: (_, index) =>
                    OnboardingSlide(data: _slides[index]),
              ),
            ),
            _DotsIndicator(
              count: _slides.length,
              current: _currentPage,
              activeColor: colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: FilledButton(
                key: const Key('onboarding_next_button'),
                onPressed: _next,
                child: Text(isLast ? 'Commencer' : 'Suivant'),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _DotsIndicator extends StatelessWidget {
  final int count;
  final int current;
  final Color activeColor;

  const _DotsIndicator({
    required this.count,
    required this.current,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final isActive = index == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive
                ? activeColor
                : activeColor.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
