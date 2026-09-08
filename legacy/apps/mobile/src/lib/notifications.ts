import Constants from "expo-constants";
import * as Notifications from "expo-notifications";
import { Platform } from "react-native";

Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldPlaySound: false,
    shouldSetBadge: false,
    shouldShowBanner: true,
    shouldShowList: true,
  }),
});

function getProjectId(): string | undefined {
  const fromConfig = (
    Constants?.expoConfig as { extra?: { eas?: { projectId?: string } } } | null
  )?.extra?.eas?.projectId;
  const fromEas = (Constants as { easConfig?: { projectId?: string } })
    ?.easConfig?.projectId;
  return fromConfig ?? fromEas;
}

/**
 * Requests notification permission and, when an EAS projectId is available,
 * returns an Expo push token. Never throws: a missing projectId (no EAS setup
 * yet) or any failure resolves to null so onboarding never crashes.
 */
export async function registerDailyHadithNotifications(): Promise<
  string | null
> {
  try {
    const permission = await Notifications.requestPermissionsAsync();
    if (!permission.granted) return null;

    if (Platform.OS === "android") {
      await Notifications.setNotificationChannelAsync("daily-hadith", {
        name: "Daily Hadith",
        importance: Notifications.AndroidImportance.DEFAULT,
      });
    }

    const projectId = getProjectId();
    if (!projectId) return null;

    const token = await Notifications.getExpoPushTokenAsync({ projectId });
    return token.data;
  } catch {
    return null;
  }
}
