// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tracking_issue.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Interruption en cours, ou `null` si tout va bien.
///
/// `keepAlive` : l'interruption ne doit pas disparaître parce que le livreur a
/// changé d'onglet. Elle survit tant que la cause n'est pas levée.

@ProviderFor(TrackingIssueController)
final trackingIssueControllerProvider = TrackingIssueControllerProvider._();

/// Interruption en cours, ou `null` si tout va bien.
///
/// `keepAlive` : l'interruption ne doit pas disparaître parce que le livreur a
/// changé d'onglet. Elle survit tant que la cause n'est pas levée.
final class TrackingIssueControllerProvider
    extends $NotifierProvider<TrackingIssueController, TrackingIssue?> {
  /// Interruption en cours, ou `null` si tout va bien.
  ///
  /// `keepAlive` : l'interruption ne doit pas disparaître parce que le livreur a
  /// changé d'onglet. Elle survit tant que la cause n'est pas levée.
  TrackingIssueControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'trackingIssueControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$trackingIssueControllerHash();

  @$internal
  @override
  TrackingIssueController create() => TrackingIssueController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TrackingIssue? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TrackingIssue?>(value),
    );
  }
}

String _$trackingIssueControllerHash() =>
    r'1ad9d03ac4be7d5f7a9666e5159a7936c2a57311';

/// Interruption en cours, ou `null` si tout va bien.
///
/// `keepAlive` : l'interruption ne doit pas disparaître parce que le livreur a
/// changé d'onglet. Elle survit tant que la cause n'est pas levée.

abstract class _$TrackingIssueController extends $Notifier<TrackingIssue?> {
  TrackingIssue? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<TrackingIssue?, TrackingIssue?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TrackingIssue?, TrackingIssue?>,
              TrackingIssue?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
