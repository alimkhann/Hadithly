import { themes } from "@hadithly/design-tokens";
import { ReactNode } from "react";
import { StyleSheet, Text, TextStyle } from "react-native";

export function Title({ children, style }: { children: ReactNode; style?: TextStyle }) {
  return <Text style={[styles.title, style]}>{children}</Text>;
}

export function Body({ children, style }: { children: ReactNode; style?: TextStyle }) {
  return <Text style={[styles.body, style]}>{children}</Text>;
}

export function Eyebrow({ children, style }: { children: ReactNode; style?: TextStyle }) {
  return <Text style={[styles.eyebrow, style]}>{children}</Text>;
}

const styles = StyleSheet.create({
  title: {
    color: themes.light.text,
    fontSize: 31,
    fontWeight: "700",
    letterSpacing: 0,
    lineHeight: 36
  },
  body: {
    color: themes.light.textSec,
    fontSize: 15,
    lineHeight: 23
  },
  eyebrow: {
    color: themes.light.accentText,
    fontSize: 12,
    fontWeight: "700",
    letterSpacing: 0,
    textTransform: "uppercase"
  }
});
