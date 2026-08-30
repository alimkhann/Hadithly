import { createContext, ReactNode, useContext } from "react";

type AuthRuntime = {
  clerkEnabled: boolean;
  convexEnabled: boolean;
};

const AuthRuntimeContext = createContext<AuthRuntime>({
  clerkEnabled: false,
  convexEnabled: false,
});

export function AuthRuntimeProvider({
  children,
  value,
}: {
  children: ReactNode;
  value: AuthRuntime;
}) {
  return (
    <AuthRuntimeContext.Provider value={value}>
      {children}
    </AuthRuntimeContext.Provider>
  );
}

export function useAuthRuntime() {
  return useContext(AuthRuntimeContext);
}
