import { AuthPage } from '@refinedev/antd'
import { useLogin } from '@refinedev/core'
import { Button, Card, Checkbox, Form, Input, Typography, theme } from 'antd'
import { useMemo } from 'react'

/**
 * "Remember me" 로 기억하는 값 — 이메일뿐이다. 세션 유지는 이미
 * supabaseAuthClient 의 persistSession 이 하고 있어 체크박스와 무관하고,
 * 비밀번호는 localStorage 에 남기지 않는다.
 */
const REMEMBERED_EMAIL_KEY = 'facely-console:remembered-email'

type LoginFormValues = {
  email: string
  password: string
  remember: boolean
}

/**
 * refine 기본 <AuthPage type="login"> 은 비밀번호를 `<Input type="password">`
 * 로 하드코딩하고 카드 제목도 번역 키로만 노출해서, prop 으로는 둘 다 못 바꾼다.
 * (formProps 로 넘긴 children 은 AuthPage 가 명시한 children 에 밀린다.)
 *
 * 그래서 renderContent 로 카드만 우리 것으로 갈아끼운다. 바깥 Layout·중앙 정렬·
 * 상단 타이틀은 AuthPage 가 준 것을 그대로 쓴다.
 */
export const LoginPage = () => (
  <AuthPage
    type="login"
    title="Facely Console"
    renderContent={(_content, pageTitle) => (
      <>
        {pageTitle}
        <LoginCard />
      </>
    )}
  />
)

/** 카드 치수·여백은 refine 기본 AuthPage 값 그대로 옮긴 것. */
const CARD_STYLE = {
  maxWidth: '400px',
  margin: 'auto',
  padding: '32px',
  boxShadow:
    '0px 2px 4px rgba(0, 0, 0, 0.02), 0px 1px 6px -1px rgba(0, 0, 0, 0.02), 0px 1px 2px rgba(0, 0, 0, 0.03)',
} as const

const TITLE_STYLE = {
  textAlign: 'center',
  marginBottom: 0,
  fontSize: '24px',
  lineHeight: '32px',
  fontWeight: 700,
} as const

function LoginCard() {
  const { token } = theme.useToken()
  const { mutate: login, isPending } = useLogin()
  // 첫 렌더에 한 번만 읽는다. 이후 값이 바뀌어도 폼 입력 중에 덮어쓰면 안 된다.
  const rememberedEmail = useMemo(
    () => localStorage.getItem(REMEMBERED_EMAIL_KEY) ?? '',
    [],
  )

  const onFinish = ({ remember, ...credentials }: LoginFormValues) => {
    if (remember) {
      localStorage.setItem(REMEMBERED_EMAIL_KEY, credentials.email)
    } else {
      localStorage.removeItem(REMEMBERED_EMAIL_KEY)
    }
    login(credentials)
  }

  return (
    <Card
      title={
        <Typography.Title
          level={3}
          style={{ ...TITLE_STYLE, color: token.colorPrimaryTextHover }}
        >
          시스템 로그인
        </Typography.Title>
      }
      styles={{
        header: { borderBottom: 0, padding: 0 },
        body: { padding: 0, marginTop: '32px' },
      }}
      style={{ ...CARD_STYLE, backgroundColor: token.colorBgElevated }}
    >
      <Form
        layout="vertical"
        requiredMark={false}
        initialValues={{
          email: rememberedEmail,
          remember: rememberedEmail !== '',
        }}
        onFinish={onFinish}
      >
        <Form.Item
          name="email"
          label="Email"
          rules={[
            { required: true, message: 'Email is required' },
            { type: 'email', message: 'Invalid email address' },
          ]}
        >
          <Input size="large" placeholder="Email" />
        </Form.Item>
        <Form.Item
          name="password"
          label="Password"
          rules={[{ required: true, message: 'Password is required' }]}
        >
          {/* Input.Password 의 기본 visibilityToggle 이 우측 눈/눈-감김 아이콘. */}
          <Input.Password
            size="large"
            autoComplete="current-password"
            placeholder="●●●●●●●●"
          />
        </Form.Item>
        <Form.Item name="remember" valuePropName="checked">
          <Checkbox style={{ fontSize: '12px' }}>Remember me</Checkbox>
        </Form.Item>
        <Form.Item style={{ marginBottom: 0 }}>
          <Button
            type="primary"
            size="large"
            htmlType="submit"
            loading={isPending}
            block
          >
            Sign in
          </Button>
        </Form.Item>
      </Form>
    </Card>
  )
}
