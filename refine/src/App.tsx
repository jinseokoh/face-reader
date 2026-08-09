import { Authenticated, Refine } from '@refinedev/core'
import { DevtoolsPanel, DevtoolsProvider } from '@refinedev/devtools'
import { RefineKbar, RefineKbarProvider } from '@refinedev/kbar'

import {
    AuthPage,
    ErrorComponent,
    ThemedLayout,
    ThemedSider,
    useNotificationProvider,
} from '@refinedev/antd'
import '@refinedev/antd/dist/reset.css'

import {
    AppstoreOutlined,
    ClusterOutlined,
    DollarOutlined,
    FlagOutlined,
    PictureOutlined,
    PlaySquareOutlined,
    ScanOutlined,
    SettingOutlined,
    TeamOutlined,
    UnlockOutlined,
} from '@ant-design/icons'
import routerProvider, {
    CatchAllNavigate,
    DocumentTitleHandler,
    UnsavedChangesNotifier,
} from '@refinedev/react-router'
import { liveProvider } from '@refinedev/supabase'
import { App as AntdApp } from 'antd'
import { BrowserRouter, Outlet, Route, Routes } from 'react-router'
import { Header } from './components/header'
import { ColorModeContextProvider } from './contexts/color-mode'
import { AdImageCreate, AdImageList } from './pages/ad-images'
import { AdVideoCreate, AdVideoList } from './pages/ad-videos'
import { CoinList } from './pages/coins'
import { DashboardPage } from './pages/dashboard'
import { MetricList, MetricShow } from './pages/metrics'
import { ReportList, ReportShow } from './pages/reports'
import { SystemPage } from './pages/system'
import { TeamList, TeamShow } from './pages/teams'
import { CompatibilityList, CompatibilityShow } from './pages/compatibilities'
import { UserList, UserShow } from './pages/users'
import authProvider from './providers/auth'
import { dataProvider } from './providers/data'
import { supabaseClient } from './providers/supabase-client'

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
                    name: 'dashboard',
                    list: '/',
                    meta: { label: '대시보드', icon: <AppstoreOutlined /> },
                  },
                  {
                    name: 'users',
                    list: '/users',
                    show: '/users/show/:id',
                    meta: { label: '사용자', icon: <TeamOutlined /> },
                  },
                  {
                    name: 'metrics',
                    list: '/metrics',
                    show: '/metrics/show/:id',
                    meta: { label: '관상 metrics', icon: <ScanOutlined /> },
                  },
                  {
                    name: 'compatibilities',
                    list: '/compatibilities',
                    show: '/compatibilities/show/:id',
                    meta: { label: '궁합 compatibilities', icon: <UnlockOutlined /> },
                  },
                  {
                    name: 'teams',
                    list: '/teams',
                    show: '/teams/show/:id',
                    meta: { label: '케미 teams', icon: <ClusterOutlined /> },
                  },
                  {
                    name: 'coins',
                    list: '/coins',
                    meta: { label: '코인 coins', icon: <DollarOutlined /> },
                  },
                  {
                    name: 'team_reports',
                    list: '/reports',
                    show: '/reports/show/:id',
                    meta: { label: '신고 reports', icon: <FlagOutlined /> },
                  },
                  {
                    name: 'ad_videos',
                    list: '/ad-videos',
                    create: '/ad-videos/create',
                    meta: { label: '영상 광고', icon: <PlaySquareOutlined /> },
                  },
                  {
                    name: 'ad_images',
                    list: '/ad-images',
                    create: '/ad-images/create',
                    meta: { label: '배너 광고', icon: <PictureOutlined /> },
                  },
                  {
                    name: 'app_config',
                    list: '/system',
                    meta: { label: '시스템', icon: <SettingOutlined /> },
                  },
                ]}
                options={{
                  syncWithLocation: true,
                  warnWhenUnsavedChanges: true,
                  projectId: 'FjBVsV-7E0eT7-WY0LgR',
                  title: {
                    icon: (
                      <img
                        src="/logo.svg"
                        alt=""
                        style={{ width: '100%', height: '100%' }}
                      />
                    ),
                    text: 'Facely Console',
                  },
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
                    <Route path="/metrics">
                      <Route index element={<MetricList />} />
                      <Route path="show/:id" element={<MetricShow />} />
                    </Route>
                    <Route path="/coins" element={<CoinList />} />
                    <Route path="/reports">
                      <Route index element={<ReportList />} />
                      <Route path="show/:id" element={<ReportShow />} />
                    </Route>
                    <Route path="/compatibilities">
                      <Route index element={<CompatibilityList />} />
                      <Route path="show/:id" element={<CompatibilityShow />} />
                    </Route>
                    <Route path="/teams">
                      <Route index element={<TeamList />} />
                      <Route path="show/:id" element={<TeamShow />} />
                    </Route>
                    <Route path="/ad-videos">
                      <Route index element={<AdVideoList />} />
                      <Route path="create" element={<AdVideoCreate />} />
                    </Route>
                    <Route path="/ad-images">
                      <Route index element={<AdImageList />} />
                      <Route path="create" element={<AdImageCreate />} />
                    </Route>
                    <Route path="/system" element={<SystemPage />} />
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
                          title="Facely Console"
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
                {/* refine 기본 문서 제목의 " | Refine" 접미사를 " | Facely" 로.
                    resource 가 없는 경로(로그인·404)는 접미사 없이 "Refine"
                    한 단어라 같은 치환으로 "Facely" 가 된다. */}
                <DocumentTitleHandler
                  handler={({ autoGeneratedTitle }) =>
                    autoGeneratedTitle.replace(/Refine$/, 'Facely')
                  }
                />
              </Refine>
              <DevtoolsPanel />
            </DevtoolsProvider>
          </AntdApp>
        </ColorModeContextProvider>
      </RefineKbarProvider>
    </BrowserRouter>
  )
}

export default App
