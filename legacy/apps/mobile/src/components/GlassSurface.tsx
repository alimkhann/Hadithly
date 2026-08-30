import { GlassView, isGlassEffectAPIAvailable, isLiquidGlassAvailable } from "expo-glass-effect";
import { ReactNode } from "react";
import { Platform, StyleSheet, View, ViewStyle } from "react-native";

type GlassVariant = "regular" | "clear";
type GlassColorScheme = "auto" | "light" | "dark";

export function canUseNativeLiquidGlass() {
  return Platform.OS === "ios" && isGlassEffectAPIAvailable() && isLiquidGlassAvailable();
}

export function GlassSurface({
  children,
  style,
  variant = "regular",
  interactive = false,
  colorScheme = "light"
}: {
  children: ReactNode;
  style?: ViewStyle | ViewStyle[];
  variant?: GlassVariant;
  interactive?: boolean;
  colorScheme?: GlassColorScheme;
}) {
  if (canUseNativeLiquidGlass()) {
    return (
      <GlassView
        colorScheme={colorScheme}
        glassEffectStyle={variant}
        isInteractive={interactive}
        style={[styles.base, style]}
      >
        {children}
      </GlassView>
    );
  }

  return <View style={[styles.base, styles.fallback, colorScheme === "dark" && styles.darkFallback, style]}>{children}</View>;
}

const styles = StyleSheet.create({
  base: {
    borderRadius: 18,
    overflow: "hidden"
  },
  fallback: {
    backgroundColor: Platform.OS === "android" ? "rgba(255,255,255,0.90)" : "rgba(255,255,255,0.72)",
    borderColor: "rgba(24,24,27,0.10)",
    borderWidth: StyleSheet.hairlineWidth,
    elevation: 8,
    shadowColor: "#000",
    shadowOffset: { height: 10, width: 0 },
    shadowOpacity: 0.10,
    shadowRadius: 22
  },
  darkFallback: {
    backgroundColor: "rgba(24,24,27,0.72)",
    borderColor: "rgba(255,255,255,0.12)"
  }
});
