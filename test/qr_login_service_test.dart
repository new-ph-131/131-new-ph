// FILE: test/qr_login_service_test.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pharoah_erp/web_live_sync/components/web_login_card.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pharoah_erp/web_live_sync/qr_login_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('QrLoginService Crypto & Payload Tests', () {
    test('createLocalChallenge & parseQrPayload roundtrip and invalid checks', () {
      final challenge = QrLoginService.createLocalChallenge();
      expect(challenge.sid.startsWith('QR_'), isTrue);
      expect(challenge.qrPayload.startsWith('PHAROAH_QR_V1|'), isTrue);

      final parsed = QrLoginService.parseQrPayload(challenge.qrPayload);
      expect(parsed, isNotNull);
      expect(parsed!.sid, equals(challenge.sid));
      expect(parsed.otp, equals(challenge.otp));

      expect(QrLoginService.parseQrPayload(''), isNull);
      expect(QrLoginService.parseQrPayload('upi://pay?pa=test@upi'), isNull);
      expect(QrLoginService.parseQrPayload('PHAROAH_QR_V1|short|abc'), isNull);
      expect(QrLoginService.parseQrPayload('PHAROAH_QR_V2|${challenge.sid}|${challenge.otp}'), isNull);
    });

    test('sealPayload & unsealPayload protect confidentiality and detect tampering', () {
      final challenge = QrLoginService.createLocalChallenge();
      final otherChallenge = QrLoginService.createLocalChallenge();

      final sealed = QrLoginService.sealPayload(
        {
          'storeToken': 'PH-LIVE-V3YN-Q6EZ',
          'username': 'admin',
          'password': 'SuperSecret@123',
          'companyName': 'Banwari Lal Pharma',
        },
        challenge.otp,
      );

      // Plaintext password must never appear in sealed token
      expect(sealed.contains('SuperSecret'), isFalse);
      expect(sealed.contains('PH-LIVE'), isFalse);

      final decoded = QrLoginService.unsealPayload(sealed, challenge.otp);
      expect(decoded, isNotNull);
      expect(decoded!['storeToken'], equals('PH-LIVE-V3YN-Q6EZ'));
      expect(decoded['username'], equals('admin'));
      expect(decoded['password'], equals('SuperSecret@123'));

      // Wrong OTP must fail HMAC verification
      expect(QrLoginService.unsealPayload(sealed, otherChallenge.otp), isNull);

      // Tampering a single character must fail HMAC verification
      final mutatedChar = sealed[10] == 'A' ? 'B' : 'A';
      final tampered = sealed.substring(0, 10) + mutatedChar + sealed.substring(11);
      expect(QrLoginService.unsealPayload(tampered, challenge.otp), isNull);
    });

    test('initSession -> approveSession -> pollSession lifecycle via MockClient', () async {
      final challenge = QrLoginService.createLocalChallenge();
      String storedStatus = '';
      String storedSealed = '';

      final mockClient = MockClient((req) async {
        if (req.method == 'POST') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          if (body['action'] == 'INIT') {
            expect(body['sid'], equals(challenge.sid));
            storedStatus = 'PENDING';
            return http.Response(jsonEncode({'status': 'SUCCESS'}), 200);
          }
          if (body['action'] == 'APPROVE') {
            expect(body['sid'], equals(challenge.sid));
            storedStatus = 'APPROVED';
            storedSealed = body['sealedPayload'] as String;
            return http.Response(jsonEncode({'status': 'SUCCESS'}), 200);
          }
        }
        if (req.method == 'GET') {
          if (storedStatus == 'PENDING') {
            return http.Response(jsonEncode({'status': 'PENDING'}), 200);
          }
          if (storedStatus == 'APPROVED') {
            final payload = storedSealed;
            storedStatus = 'EXPIRED'; // Single-use burn on server
            return http.Response(
              jsonEncode({'status': 'APPROVED', 'sealedPayload': payload}),
              200,
            );
          }
          return http.Response(jsonEncode({'status': 'EXPIRED'}), 200);
        }
        return http.Response('Not found', 404);
      });

      expect(await QrLoginService.initSession(challenge.sid, client: mockClient), isTrue);

      final poll1 = await QrLoginService.pollSession(
        sid: challenge.sid,
        otp: challenge.otp,
        client: mockClient,
      );
      expect(poll1.status, equals(QrPollStatus.pending));

      final approveRes = await QrLoginService.approveSession(
        sid: challenge.sid,
        otp: challenge.otp,
        storeToken: 'PH-LIVE-TEST-9999',
        username: 'Admin',
        password: 'pass123',
        companyName: 'Test Store',
        client: mockClient,
      );
      expect(approveRes.success, isTrue);

      final poll2 = await QrLoginService.pollSession(
        sid: challenge.sid,
        otp: challenge.otp,
        client: mockClient,
      );
      expect(poll2.status, equals(QrPollStatus.approved));
      expect(poll2.credentials?.storeToken, equals('PH-LIVE-TEST-9999'));
      expect(poll2.credentials?.username, equals('admin'));
      expect(poll2.credentials?.password, equals('pass123'));

      // Second poll after burn must report expired
      final poll3 = await QrLoginService.pollSession(
        sid: challenge.sid,
        otp: challenge.otp,
        client: mockClient,
      );
      expect(poll3.status, equals(QrPollStatus.expired));
    });
  });

  group('WebLoginCard Dual UI Tests', () {
    testWidgets('renders both Manual Credentials form and Instant QR Login side-by-side', (tester) async {
      tester.view.physicalSize = const Size(1280, 840);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      String? loggedToken;
      String? loggedUser;
      String? loggedPass;

      final mockClient = MockClient((req) async {
        if (req.method == 'POST') {
          return http.Response(jsonEncode({'status': 'SUCCESS'}), 200);
        }
        return http.Response(jsonEncode({'status': 'PENDING'}), 200);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WebLoginCard(
              qrHttpClient: mockClient,
              onLogin: (t, u, p) {
                loggedToken = t;
                loggedUser = u;
                loggedPass = p;
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('PHAROAH WEB WORKSTATION'), findsOneWidget);
      expect(find.text('INSTANT QR LOGIN'), findsOneWidget);
      expect(find.text('LOGIN TO WORKSTATION'), findsOneWidget);

      // Verify manual login still works unchanged
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(3));
      await tester.enterText(fields.at(0), 'PH-LIVE-ABCD-1234');
      await tester.enterText(fields.at(1), 'Admin');
      await tester.enterText(fields.at(2), 'secret99');
      await tester.tap(find.text('LOGIN TO WORKSTATION'));
      await tester.pump();

      expect(loggedToken, equals('PH-LIVE-ABCD-1234'));
      expect(loggedUser, equals('admin'));
      expect(loggedPass, equals('secret99'));
    });

    testWidgets('auto-logs in via onLogin when QR poll returns APPROVED sealed credentials', (tester) async {
      tester.view.physicalSize = const Size(1280, 840);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      String? loggedToken;
      String? loggedUser;
      String? loggedPass;
      String? approvedSealed;

      final mockClient = MockClient((req) async {
        if (req.method == 'POST') {
          return http.Response(jsonEncode({'status': 'SUCCESS'}), 200);
        }
        if (req.method == 'GET' && approvedSealed != null) {
          return http.Response(
            jsonEncode({'status': 'APPROVED', 'sealedPayload': approvedSealed}),
            200,
          );
        }
        return http.Response(jsonEncode({'status': 'PENDING'}), 200);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WebLoginCard(
              qrHttpClient: mockClient,
              onLogin: (t, u, p) {
                loggedToken = t;
                loggedUser = u;
                loggedPass = p;
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      final qrWidget = tester.widget<QrImageView>(find.byType(QrImageView));
      final rawPayload = (qrWidget.key as ValueKey<String>).value;
      final scanned = QrLoginService.parseQrPayload(rawPayload);
      expect(scanned, isNotNull);

      approvedSealed = QrLoginService.sealPayload(
        {
          'storeToken': 'PH-LIVE-QR99-1122',
          'username': 'admin',
          'password': 'qrpass77',
          'companyName': 'QR Pharma',
        },
        scanned!.otp,
      );

      // Advance timer past 1800ms poll interval so WebLoginCard polls and auto-logs in
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(loggedToken, equals('PH-LIVE-QR99-1122'));
      expect(loggedUser, equals('admin'));
      expect(loggedPass, equals('qrpass77'));
    });
  });
}
