import { Image, ImageStyle, StyleProp } from "react-native";

export function Logo({ size = 36, dark = false, style }: { size?: number; dark?: boolean; style?: StyleProp<ImageStyle> }) {
  return (
    <Image
      source={
        dark
          ? require("../../assets/brand/hadithly-logo-dark.png")
          : require("../../assets/brand/hadithly-logo-light.png")
      }
      style={[{ height: size, width: size }, style]}
      resizeMode="contain"
    />
  );
}
