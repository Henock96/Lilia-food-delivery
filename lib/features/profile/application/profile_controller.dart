import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../models/app_user.dart';
import '../../deliveries/data/delivery_repository.dart';

part 'profile_controller.g.dart';

@Riverpod(keepAlive: true)
class ProfileController extends _$ProfileController {
  @override
  FutureOr<AppUser> build() => ref.watch(deliveryRepositoryProvider).getMe();

  Future<void> setDriverStatus(DriverStatus status) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(deliveryRepositoryProvider);
      await repo.setDriverStatus(status);
      return repo.getMe();
    });
  }
}
