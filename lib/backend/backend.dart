// backend.dart
// Barrel file — import the whole backend layer with one line:
//
//     import 'package:intelliglove/backend/backend.dart';

// Core
export 'core/enums.dart';
export 'core/firebase_refs.dart';
export 'core/firestore_utils.dart';

// Models
export 'models/app_user.dart';
export 'models/glove_device.dart';
export 'models/connection_log.dart';
export 'models/gesture_reading.dart';
export 'models/translation_session.dart';
export 'models/realtime_message.dart';
export 'models/glove_alert.dart';

// Services
export 'services/auth_service.dart';
export 'services/username_service.dart';
export 'services/user_service.dart';
export 'services/device_service.dart';
export 'services/connection_log_service.dart';
export 'services/gesture_service.dart';
export 'services/session_service.dart';
export 'services/message_service.dart';
export 'services/alert_service.dart';
export 'services/analytics_service.dart';
export 'services/storage_service.dart';
export 'services/messaging_service.dart';

// Facade
export 'glove_backend.dart';
