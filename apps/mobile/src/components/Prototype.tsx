import { themes } from "@hadithly/design-tokens";
import { ChevronRight } from "lucide-react-native";
import { ReactNode } from "react";
import { Pressable, StyleSheet, Text, View, ViewStyle } from "react-native";

import { GlassSurface } from "@/components/GlassSurface";

const t = themes.light;

export function Card({ children, style, padding = 14 }: { children: ReactNode; style?: ViewStyle | ViewStyle[]; padding?: number }) {
  return <View style={[styles.card, { padding }, style]}>{children}</View>;
}

export function SectionHeader({ children, right }: { children: ReactNode; right?: ReactNode }) {
  return (
    <View style={styles.sectionHeader}>
      <Text style={styles.sectionTitle}>{children}</Text>
      {right}
    </View>
  );
}

export function Chip({
  children,
  variant = "secondary",
  tone = "default",
  style
}: {
  children: ReactNode;
  variant?: "outline" | "secondary" | "primary" | "soft" | "ghost";
  tone?: "default" | "gold" | "warning" | "danger";
  style?: ViewStyle | ViewStyle[];
}) {
  return (
    <View style={[styles.chip, chipVariants[variant], toneStyles[tone], style]}>
      {typeof children === "string" || typeof children === "number" ? (
        <Text style={[styles.chipText, chipTextVariants[variant], toneTextStyles[tone]]}>{children}</Text>
      ) : (
        children
      )}
    </View>
  );
}

export function Button({
  children,
  icon,
  iconRight,
  variant = "primary",
  block,
  disabled,
  onPress,
  style
}: {
  children: ReactNode;
  icon?: ReactNode;
  iconRight?: ReactNode;
  variant?: "primary" | "secondary" | "outline" | "ghost" | "destructive";
  block?: boolean;
  disabled?: boolean;
  onPress?: () => void;
  style?: ViewStyle | ViewStyle[];
}) {
  return (
    <Pressable disabled={disabled} onPress={onPress} style={[styles.button, buttonVariants[variant], block && styles.block, disabled && styles.disabled, style]}>
      {icon}
      <Text style={[styles.buttonText, buttonTextVariants[variant]]}>{children}</Text>
      {iconRight}
    </Pressable>
  );
}

export function PrimaryButton({ children, iconRight }: { children: ReactNode; iconRight?: ReactNode }) {
  return <Button iconRight={iconRight}>{children}</Button>;
}

export function IconButton({
  children,
  size = 38,
  glass,
  onPress,
  accessibilityLabel,
  style,
  dark
}: {
  children: ReactNode;
  size?: number;
  glass?: boolean;
  onPress?: () => void;
  accessibilityLabel?: string;
  style?: ViewStyle | ViewStyle[];
  dark?: boolean;
}) {
  const content = glass ? (
    <GlassSurface colorScheme={dark ? "dark" : "light"} interactive style={styles.iconFill} variant="clear">
      {children}
    </GlassSurface>
  ) : (
    <View style={[styles.iconFill, styles.iconPlain]}>{children}</View>
  );

  return (
    <Pressable accessibilityLabel={accessibilityLabel} onPress={onPress} style={[{ height: size, width: size }, style]}>
      {content}
    </Pressable>
  );
}

export const GlassIconButton = IconButton;

export function Segmented({ options, value }: { options: string[]; value: string }) {
  return (
    <View style={styles.segmented}>
      {options.map((option) => (
        <View key={option} style={[styles.segment, option === value && styles.segmentActive]}>
          <Text style={[styles.segmentText, option === value && styles.segmentTextActive]}>{option}</Text>
        </View>
      ))}
    </View>
  );
}

export function Switch({ on = true }: { on?: boolean }) {
  return (
    <View style={[styles.switchTrack, on && styles.switchOn]}>
      <View style={[styles.switchKnob, on && styles.switchKnobOn]} />
    </View>
  );
}

export function ProgressBar({
  value,
  height = 3,
  segments
}: {
  value?: number;
  height?: number;
  segments?: Array<{ value: number; color: string }>;
}) {
  return (
    <View style={[styles.progressTrack, { height }]}>
      {segments ? (
        <View style={styles.segmentProgressRow}>
          {segments.map((segment, index) => (
            <View key={`${segment.color}-${index}`} style={{ backgroundColor: segment.color, flex: segment.value }} />
          ))}
        </View>
      ) : (
        <View style={[styles.progressFill, { width: `${Math.max(0, Math.min(100, value ?? 0))}%` }]} />
      )}
    </View>
  );
}

export function Row({
  icon,
  leading,
  title,
  subtitle,
  trailing,
  last,
  onPress
}: {
  icon?: ReactNode;
  leading?: ReactNode;
  title: ReactNode;
  subtitle?: ReactNode;
  trailing?: ReactNode;
  last?: boolean;
  onPress?: () => void;
}) {
  return (
    <Pressable onPress={onPress} style={[styles.row, last && styles.noBorder]}>
      {icon || leading ? <View style={styles.rowLeading}>{icon ?? leading}</View> : null}
      <View style={styles.rowCopy}>
        {typeof title === "string" ? <Text style={styles.rowTitle}>{title}</Text> : title}
        {subtitle ? (typeof subtitle === "string" ? <Text style={styles.rowSubtitle}>{subtitle}</Text> : subtitle) : null}
      </View>
      {trailing ?? <ChevronRight color={t.textTer} size={16} />}
    </Pressable>
  );
}

export const ReaderRow = Row;

export function TopicChip({ label, color }: { label: string; color: string }) {
  return (
    <View style={[styles.topicChip, { backgroundColor: `${color}1F`, borderColor: `${color}40` }]}>
      <View style={[styles.topicDot, { backgroundColor: color }]} />
      <Text style={[styles.topicText, { color }]}>{label}</Text>
    </View>
  );
}

export function StatCard({ value, label }: { value: string; label: string }) {
  return (
    <Card padding={12} style={styles.statCard}>
      <Text style={styles.statValue}>{value}</Text>
      <Text style={styles.statLabel}>{label}</Text>
    </Card>
  );
}

const chipVariants = StyleSheet.create({
  outline: { backgroundColor: "transparent", borderColor: t.hair, borderWidth: StyleSheet.hairlineWidth },
  secondary: { backgroundColor: t.surface2, borderColor: "transparent", borderWidth: StyleSheet.hairlineWidth },
  primary: { backgroundColor: t.accent, borderColor: "transparent", borderWidth: StyleSheet.hairlineWidth },
  soft: { backgroundColor: t.accentSoft, borderColor: "transparent", borderWidth: StyleSheet.hairlineWidth },
  ghost: { backgroundColor: "transparent", borderColor: "transparent", borderWidth: StyleSheet.hairlineWidth }
});

const chipTextVariants = StyleSheet.create({
  outline: { color: t.text },
  secondary: { color: t.text },
  primary: { color: "#FFFFFF" },
  soft: { color: t.accentText },
  ghost: { color: t.textSec }
});

const toneStyles = StyleSheet.create({
  default: {},
  gold: { backgroundColor: `${t.gold}1F` },
  warning: { borderColor: "#D97706" },
  danger: { borderColor: t.danger }
});

const toneTextStyles = StyleSheet.create({
  default: {},
  gold: { color: t.gold },
  warning: { color: "#D97706" },
  danger: { color: t.danger }
});

const buttonVariants = StyleSheet.create({
  primary: { backgroundColor: t.accent, borderColor: "transparent" },
  secondary: { backgroundColor: t.surface2, borderColor: "transparent" },
  outline: { backgroundColor: "transparent", borderColor: t.hair },
  ghost: { backgroundColor: "transparent", borderColor: "transparent" },
  destructive: { backgroundColor: t.danger, borderColor: "transparent" }
});

const buttonTextVariants = StyleSheet.create({
  primary: { color: "#FFFFFF" },
  secondary: { color: t.text },
  outline: { color: t.text },
  ghost: { color: t.textSec },
  destructive: { color: "#FFFFFF" }
});

const styles = StyleSheet.create({
  card: {
    backgroundColor: t.surface,
    borderColor: t.hair,
    borderRadius: 10,
    borderWidth: StyleSheet.hairlineWidth,
    shadowColor: "#000",
    shadowOffset: { height: 7, width: 0 },
    shadowOpacity: 0.04,
    shadowRadius: 18
  },
  sectionHeader: {
    alignItems: "center",
    flexDirection: "row",
    justifyContent: "space-between",
    marginBottom: 9
  },
  sectionTitle: {
    color: t.textSec,
    fontSize: 13,
    fontWeight: "600"
  },
  chip: {
    alignItems: "center",
    borderRadius: 7,
    justifyContent: "center",
    minHeight: 18,
    paddingHorizontal: 7,
    paddingVertical: 2
  },
  chipText: {
    fontSize: 10.5,
    fontWeight: "600",
    lineHeight: 13
  },
  button: {
    alignItems: "center",
    borderRadius: 7,
    borderWidth: StyleSheet.hairlineWidth,
    flexDirection: "row",
    gap: 7,
    justifyContent: "center",
    minHeight: 38,
    paddingHorizontal: 14,
    paddingVertical: 9
  },
  buttonText: {
    fontSize: 14,
    fontWeight: "600"
  },
  block: {
    width: "100%"
  },
  disabled: {
    opacity: 0.45
  },
  iconFill: {
    alignItems: "center",
    borderRadius: 12,
    flex: 1,
    justifyContent: "center"
  },
  iconPlain: {
    backgroundColor: "transparent"
  },
  segmented: {
    backgroundColor: t.surface2,
    borderRadius: 999,
    flexDirection: "row",
    padding: 3
  },
  segment: {
    borderRadius: 999,
    paddingHorizontal: 10,
    paddingVertical: 5
  },
  segmentActive: {
    backgroundColor: t.surface
  },
  segmentText: {
    color: t.textSec,
    fontSize: 11.5,
    fontWeight: "600"
  },
  segmentTextActive: {
    color: t.text
  },
  switchTrack: {
    backgroundColor: t.hair,
    borderRadius: 12,
    height: 24,
    padding: 2,
    width: 44
  },
  switchOn: {
    backgroundColor: t.accent
  },
  switchKnob: {
    backgroundColor: "#FFFFFF",
    borderRadius: 10,
    height: 20,
    width: 20
  },
  switchKnobOn: {
    marginLeft: 20
  },
  progressTrack: {
    backgroundColor: t.hair,
    borderRadius: 99,
    overflow: "hidden",
    width: "100%"
  },
  segmentProgressRow: {
    flexDirection: "row",
    height: "100%",
    width: "100%"
  },
  progressFill: {
    backgroundColor: t.accent,
    borderRadius: 99,
    height: "100%"
  },
  row: {
    alignItems: "center",
    borderBottomColor: t.hair,
    borderBottomWidth: StyleSheet.hairlineWidth,
    flexDirection: "row",
    gap: 12,
    minHeight: 58,
    paddingVertical: 12
  },
  noBorder: {
    borderBottomWidth: 0
  },
  rowLeading: {
    alignItems: "center",
    minWidth: 30
  },
  rowCopy: {
    flex: 1,
    minWidth: 0
  },
  rowTitle: {
    color: t.text,
    fontSize: 14.5,
    fontWeight: "600"
  },
  rowSubtitle: {
    color: t.textSec,
    fontSize: 12,
    lineHeight: 17,
    marginTop: 2
  },
  topicChip: {
    alignItems: "center",
    borderRadius: 999,
    borderWidth: StyleSheet.hairlineWidth,
    flexDirection: "row",
    gap: 7,
    paddingHorizontal: 12,
    paddingVertical: 7
  },
  topicDot: {
    borderRadius: 3,
    height: 6,
    width: 6
  },
  topicText: {
    fontSize: 13,
    fontWeight: "600"
  },
  statCard: {
    alignItems: "center",
    flex: 1
  },
  statValue: {
    color: t.text,
    fontSize: 20,
    fontWeight: "700"
  },
  statLabel: {
    color: t.textSec,
    fontSize: 11,
    marginTop: 2
  }
});
