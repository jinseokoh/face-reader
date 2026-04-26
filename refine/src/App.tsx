import { Authenticated, Refine } from "@refinedev/core";
import { DevtoolsPanel, DevtoolsProvider } from "@refinedev/devtools";
import { RefineKbar, RefineKbarProvider } from "@refinedev/kbar";

import {
  AuthPage,
  ErrorComponent,
  ThemedLayout,
  ThemedSider,
  useNotificationProvider,
} from "@refinedev/antd";
import "@refinedev/antd/dist/reset.css";

import {
  AppstoreOutlined,
  DollarOutlined,
  ScanOutlined,
  TeamOutlined,
  UnlockOutlined,
} from "@ant-design/icons";
import routerProvider, {
  CatchAllNavigate,
  DocumentTitleHandler,
  UnsavedChangesNotifier,
} from "@refinedev/react-router";
import { liveProvider } from "@refinedev/supabase";
import { App as AntdApp } from "antd";
import { BrowserRouter, Outlet, Route, Routes } from "react-router";
import { Header } from "./components/header";
import { ColorModeContextProvider } from "./contexts/color-mode";
import { CoinList } from "./pages/coins";
import { DashboardPage } from "./pages/dashboard";
import { MetricList } from "./pages/metrics";
import { UnlockList } from "./pages/unlocks";
import { UserList, UserShow } from "./pages/users";
import authProvider from "./providers/auth";
import { dataProvider } from "./providers/data";
import { supabaseClient } from "./providers/supabase-client";

function App() {
  return (
    <BrowserRouter>
      <RefineKbarProvider>
        <ColorModeContextProvider>
          <AntdApp>
            <DevtoolsProvider>
              <Refine
                dataProvider={dataProvider}
                liveProvider={liveProvider(supabaseClient)}
                authProvider={authProvider}
                routerProvider={routerProvider}
                notificationProvider={useNotificationProvider}
                resources={[
                  {
                    name: "dashboard",
                    list: "/",
                    meta: { label: "대시보드", icon: <AppstoreOutlined /> },
                  },
                  {
                    name: "users",
                    list: "/users",
                    show: "/users/show/:id",
                    meta: { label: "가입자", icon: <TeamOutlined /> },
                  },
                  {
                    name: "metrics",
                    list: "/metrics",
                    meta: { label: "관상 업로드", icon: <ScanOutlined /> },
                  },
                  {
                    name: "coins",
                    list: "/coins",
                    meta: { label: "코인 ledger", icon: <DollarOutlined /> },
                  },
                  {
                    name: "unlocks",
                    list: "/unlocks",
                    meta: { label: "궁합 unlock", icon: <UnlockOutlined /> },
                  },
                ]}
                options={{
                  syncWithLocation: true,
                  warnWhenUnsavedChanges: true,
                  projectId: "FjBVsV-7E0eT7-WY0LgR",
                  title: { text: "Face Reader Admin" },
                }}
              >
                <Routes>
                  <Route
                    element={
                      <Authenticated
                        key="authenticated-inner"
                        fallback={<CatchAllNavigate to="/login" />}
                      >
                        <ThemedLayout
                          Header={Header}
                          Sider={(props) => <ThemedSider {...props} fixed />}
                        >
                          <Outlet />
                        </ThemedLayout>
                      </Authenticated>
                    }
                  >
                    <Route index element={<DashboardPage />} />
                    <Route path="/users">
                      <Route index element={<UserList />} />
                      <Route path="show/:id" element={<UserShow />} />
                    </Route>
                    <Route path="/metrics" element={<MetricList />} />
                    <Route path="/coins" element={<CoinList />} />
                    <Route path="/unlocks" element={<UnlockList />} />
                    <Route path="*" element={<ErrorComponent />} />
                  </Route>
                  <Route
                    element={
                      <Authenticated
                        key="authenticated-outer"
                        fallback={<Outlet />}
                      >
                        <Outlet />
                      </Authenticated>
                    }
                  >
                    <Route
                      path="/login"
                      element={
                        <AuthPage
                          type="login"
                          title="Face Reader Admin"
                          formProps={{
                            initialValues: {},
                          }}
                          providers={[]}
                          registerLink={false}
                          forgotPasswordLink={false}
                        />
                      }
                    />
                  </Route>
                </Routes>

                <RefineKbar />
                <UnsavedChangesNotifier />
                <DocumentTitleHandler />
              </Refine>
              <DevtoolsPanel />
            </DevtoolsProvider>
          </AntdApp>
        </ColorModeContextProvider>
      </RefineKbarProvider>
    </BrowserRouter>
  );
}

export default App;
