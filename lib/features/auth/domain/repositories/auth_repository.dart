import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sixam_mart_store/api/api_client.dart';
import 'package:sixam_mart_store/features/business/domain/models/package_model.dart';
import 'package:sixam_mart_store/util/app_constants.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixam_mart_store/features/auth/domain/repositories/auth_repository_interface.dart';

class AuthRepository implements AuthRepositoryInterface {
  final ApiClient apiClient;
  final SharedPreferences sharedPreferences;
  AuthRepository({required this.apiClient, required this.sharedPreferences});

  @override
  Future<Response> login(String? email, String password, String type) async {
    return await apiClient.postData(AppConstants.loginUri, {"email": email, "password": password, 'vendor_type': type}, handleError: false);
  }

  @override
  Future<Response> registerRestaurant(Map<String, String> data, XFile? logo, XFile? cover, List<MultipartDocument> tinFiles) async {
    return await apiClient.postMultipartData(AppConstants.restaurantRegisterUri, data, [MultipartBody('logo', logo), MultipartBody('cover_photo', cover)], multipartDocument: tinFiles);
  }

  @override
  Future<Response> updateToken() async {
    String? deviceToken;
    try {
      if (GetPlatform.isIOS) {
        await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
        NotificationSettings settings = await FirebaseMessaging.instance.requestPermission(
          alert: true, announcement: false, badge: true, carPlay: false,
          criticalAlert: false, provisional: false, sound: true,
        );
        if(settings.authorizationStatus == AuthorizationStatus.authorized) {
          deviceToken = await _saveDeviceToken();
        }
      }else {
        deviceToken = await _saveDeviceToken();
      }
      if(!GetPlatform.isWeb) {
        await FirebaseMessaging.instance.subscribeToTopic(AppConstants.topic);
        String? zoneTopic = sharedPreferences.getString(AppConstants.zoneTopic);
        if(zoneTopic != null && zoneTopic.isNotEmpty) {
          await FirebaseMessaging.instance.subscribeToTopic(zoneTopic);
        }
      }
    } catch (e) {
      // Non-fatal: FCM/APNs issues must not break login or app navigation.
      // The token (if obtained) is still sent below; the server handles an
      // empty/null fcm_token gracefully.
      if (kDebugMode) {
        print('---- FirebaseMessaging setup failed (non-fatal): $e');
      }
    }
    return await apiClient.postData(AppConstants.tokenUri, {"_method": "put", "token": getUserToken(), "fcm_token": deviceToken}, handleError: false);
  }

  Future<String?> _saveDeviceToken() async {
    String? deviceToken = '';
    if(!GetPlatform.isWeb) {
      try {
        deviceToken = await FirebaseMessaging.instance.getToken();
      } catch (e) {
        // On iOS release builds with misconfigured Firebase (wrong bundle id in
        // GoogleService-Info.plist, missing APNs key, etc.) getToken() can
        // return null or throw. Don't crash — just return empty string.
        if (kDebugMode) {
          print('---- FirebaseMessaging.getToken() failed (non-fatal): $e');
        }
        deviceToken = '';
      }
    }
    if (kDebugMode) {
      print('-----Device Token----- $deviceToken');
    }
    return deviceToken;
  }

  @override
  Future<bool> saveUserToken(String token, String zoneTopic, String type) async {
    apiClient.updateHeader(token, sharedPreferences.getString(AppConstants.languageCode), null, type);
    sharedPreferences.setString(AppConstants.zoneTopic, zoneTopic);
    sharedPreferences.setString(AppConstants.type, type);
    return await sharedPreferences.setString(AppConstants.token, token);
  }

  @override
  String getUserToken() {
    return sharedPreferences.getString(AppConstants.token) ?? "";
  }

  @override
  bool isLoggedIn() {
    return sharedPreferences.containsKey(AppConstants.token);
  }

  @override
  Future<bool> clearSharedData() async {
    if(!GetPlatform.isWeb) {
      try {
        await apiClient.postData(AppConstants.tokenUri, {"_method": "put", "token": getUserToken(), "fcm_token": '@'}, handleError: false);
        String? zoneTopic = sharedPreferences.getString(AppConstants.zoneTopic);
        if(zoneTopic != null && zoneTopic.isNotEmpty) {
          await FirebaseMessaging.instance.unsubscribeFromTopic(zoneTopic);
        }
      } catch (e) {
        if (kDebugMode) {
          print('---- clearSharedData(): FCM cleanup failed (non-fatal): $e');
        }
      }
    }
    await sharedPreferences.remove(AppConstants.token);
    await sharedPreferences.remove(AppConstants.userAddress);
    await sharedPreferences.remove(AppConstants.type);
    await sharedPreferences.remove(AppConstants.moduleType);
    return true;
  }

  @override
  Future<void> saveUserNumberAndPassword(String number, String password, String type) async {
    try {
      await sharedPreferences.setString(AppConstants.userPassword, password);
      await sharedPreferences.setString(AppConstants.userNumber, number);
      await sharedPreferences.setString(AppConstants.userType, type);
    } catch (e) {
      rethrow;
    }
  }

  @override
  String getUserNumber() {
    return sharedPreferences.getString(AppConstants.userNumber) ?? "";
  }

  @override
  String getUserPassword() {
    return sharedPreferences.getString(AppConstants.userPassword) ?? "";
  }

  @override
  String getUserType() {
    return sharedPreferences.getString(AppConstants.type) ?? "";
  }

  @override
  bool isNotificationActive() {
    return sharedPreferences.getBool(AppConstants.notification) ?? true;
  }

  @override
  Future<void> setNotificationActive(bool isActive) async{
    if(isActive) {
      try {
        await updateToken();
      } catch (e) {
        if (kDebugMode) {
          print('---- setNotificationActive(true): updateToken failed (non-fatal): $e');
        }
      }
    }else {
      if(!GetPlatform.isWeb) {
        try {
          await apiClient.postData(AppConstants.tokenUri, {"_method": "put", "token": getUserToken(), "fcm_token": '@'}, handleError: false);
          await FirebaseMessaging.instance.unsubscribeFromTopic(AppConstants.topic);
          String? zoneTopic = sharedPreferences.getString(AppConstants.zoneTopic);
          if(zoneTopic != null && zoneTopic.isNotEmpty) {
            await FirebaseMessaging.instance.unsubscribeFromTopic(zoneTopic);
          }
        } catch (e) {
          if (kDebugMode) {
            print('---- setNotificationActive(false): FCM cleanup failed (non-fatal): $e');
          }
        }
      }
    }
    sharedPreferences.setBool(AppConstants.notification, isActive);
  }

  @override
  Future<bool> clearUserNumberAndPassword() async {
    await sharedPreferences.remove(AppConstants.userType);
    await sharedPreferences.remove(AppConstants.userPassword);
    return await sharedPreferences.remove(AppConstants.userNumber);
  }

  @override
  Future<bool> toggleStoreClosedStatus() async {
    Response response = await apiClient.postData(AppConstants.updateVendorStatusUri, {});
    return (response.statusCode == 200);
  }

  @override
  Future<bool> saveIsStoreRegistration(bool status) async {
    return await sharedPreferences.setBool(AppConstants.isStoreRegister, status);
  }

  @override
  bool getIsStoreRegistration() {
    return sharedPreferences.getBool(AppConstants.isStoreRegister) ?? false;
  }

  @override
  Future<PackageModel?> getPackageList({int? moduleId}) async {
    PackageModel? packageModel;
    Response response = await apiClient.getData('${AppConstants.restaurantPackagesUri}?module_id=$moduleId');
    if(response.statusCode == 200) {
      packageModel = PackageModel.fromJson(response.body);
    }
    return packageModel;
  }

  @override
  String getModuleType() {
    return sharedPreferences.getString(AppConstants.moduleType) ?? "";
  }

  @override
  void setModuleType(String type) {
    sharedPreferences.setString(AppConstants.moduleType, type);
  }

  @override
  Future add(value) {
    throw UnimplementedError();
  }

  @override
  Future delete(int? id) {
    throw UnimplementedError();
  }

  @override
  Future get(int? id) {
    throw UnimplementedError();
  }

  @override
  Future update(Map<String, dynamic> body) {
    throw UnimplementedError();
  }

  @override
  Future getList() {
    throw UnimplementedError();
  }

}