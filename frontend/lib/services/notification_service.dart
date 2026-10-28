import 'package:flutter/material.dart';
import 'api_service.dart';

class NotificationService {
  static final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);
  static final ValueNotifier<List<dynamic>> notificationsNotifier = ValueNotifier([]);

  static Future<Map<String, dynamic>> fetchMyNotifications() async {
    if (!ApiService.isLoggedIn) return {};
    final response = await ApiService.get('/notifications');
    if (response != null) {
      notificationsNotifier.value = response['notifications'] ?? [];
      unreadCount.value = response['unreadCount'] ?? 0;
    }
    return response ?? {};
  }

  static Future<List<dynamic>> fetchAllNotifications() async {
    // Admin route
    final response = await ApiService.get('/notifications/admin/all');
    if (response is List) return response;
    return [];
  }

  static void onNewNotificationReceived(dynamic notification) {
    unreadCount.value++;
    final currentList = List.from(notificationsNotifier.value);
    currentList.insert(0, notification);
    notificationsNotifier.value = currentList;
  }

  static Future<void> markAllRead() async {
    await ApiService.put('/notifications/mark-all-read', {});
    unreadCount.value = 0;
    
    // Locally update the list to show all as read
    final currentList = List.from(notificationsNotifier.value);
    for (var n in currentList) { n['isRead'] = true; }
    notificationsNotifier.value = currentList;
  }

  static Future<void> clearAll() async {
    await ApiService.delete('/notifications/clear-all');
    unreadCount.value = 0;
    notificationsNotifier.value = [];
  }

  static Future<void> deleteNotification(String id) async {
    await ApiService.delete('/notifications/$id');
    final currentList = List.from(notificationsNotifier.value);
    currentList.removeWhere((n) => n['_id'] == id);
    notificationsNotifier.value = currentList;
  }

  static Future<void> sendAdminNotification(Map<String, dynamic> data) async {
    await ApiService.post('/notifications', data);
  }

  static Future<void> broadcastNotification({required String title, required String body}) async {
    await sendAdminNotification({
      'title': title,
      'body': body,
      'type': 'broadcast',
      'userId': null,
    });
  }
}
