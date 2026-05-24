import * as Notifications from "expo-notifications";
import { Platform } from "react-native";

Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldPlaySound: false,
    shouldSetBadge: false,
    shouldShowBanner: true,
    shouldShowList: true
  })
});

export async function registerDailyHadithNotifications() {
  const permission = await Notifications.requestPermissionsAsync();
  if (!permission.granted) return null;

  if (Platform.OS === "android") {
    await Notifications.setNotificationChannelAsync("daily-hadith", {
      name: "Daily Hadith",
      importance: Notifications.AndroidImportance.DEFAULT
    });
  }

  const token = await Notifications.getExpoPushTokenAsync();
  return token.data;
}
