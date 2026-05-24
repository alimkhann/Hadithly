import { Tabs } from "expo-router";
import { Home, Library, Trophy, UserRound } from "lucide-react-native";

import { themes } from "@hadithly/design-tokens";

const t = themes.light;

export default function TabLayout() {
  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: t.accent,
        tabBarInactiveTintColor: t.textSec,
        tabBarLabelStyle: {
          fontSize: 11,
          fontWeight: "600"
        },
        tabBarStyle: {
          backgroundColor: "rgba(255,255,255,0.88)",
          borderColor: "rgba(24,24,27,0.10)",
          borderRadius: 24,
          borderTopWidth: 0,
          borderWidth: 1,
          bottom: 16,
          elevation: 12,
          height: 68,
          left: 16,
          paddingBottom: 8,
          paddingTop: 8,
          position: "absolute",
          right: 16,
          shadowColor: "#000",
          shadowOffset: { height: 12, width: 0 },
          shadowOpacity: 0.12,
          shadowRadius: 24
        }
      }}
    >
      <Tabs.Screen name="home" options={{ title: "Home", tabBarIcon: ({ color }) => <Home color={color} size={21} /> }} />
      <Tabs.Screen name="library" options={{ title: "Library", tabBarIcon: ({ color }) => <Library color={color} size={21} /> }} />
      <Tabs.Screen name="community" options={{ title: "Community", tabBarIcon: ({ color }) => <Trophy color={color} size={21} /> }} />
      <Tabs.Screen name="you" options={{ title: "You", tabBarIcon: ({ color }) => <UserRound color={color} size={21} /> }} />
    </Tabs>
  );
}
