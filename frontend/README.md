lib/
main.dart

app/
app.dart
router.dart

    core/
      config/
        env.dart
      logging/
        app_logger.dart
      network/
        dio_provider.dart
      errors/
        app_exception.dart

    theme/
      app_colors.dart
      app_spacing.dart
      app_radius.dart
      app_text_styles.dart
      app_theme.dart

    shared/
      widgets/
        app_button.dart
        app_text_field.dart
        app_loader.dart

    features/
      auth/
        data/
          auth_api.dart
          auth_repository.dart
          auth_local_storage.dart
        domain/
          models/
            auth_user.dart
            auth_session.dart
        presentation/
          controllers/
            auth_controller.dart
            auth_state.dart
          providers/
            auth_providers.dart
          screens/
            login_screen.dart
            register_screen.dart

      home/
        home_screen.dart
