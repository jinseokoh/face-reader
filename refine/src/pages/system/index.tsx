import { App, Alert, Button, Card, Form, Input, InputNumber, Skeleton, Space, Tag, Typography } from "antd";
import { useEffect, useState } from "react";
import { adminClient } from "../../providers/data";

const { Paragraph, Text } = Typography;

interface AppConfigValues {
  android_min_build: number;
  ios_min_build: number;
  notice: string | null;
}

/**
 * 시스템 — app_config 단일 행(id=1) 편집. 현재는 강제 업데이트 정책이 전부.
 *
 * 앱은 시작 시 이 행을 1회 조회해 `내 buildNumber < 플랫폼별 min_build` 면
 * 닫을 수 없는 업데이트 게이트를 띄운다 (조회 실패는 fail-open — 네트워크
 * 사정으로 앱을 잠그지 않는다). service_role client 라 RLS(읽기 전용) 우회
 * 쓰기가 가능 — 이 페이지가 유일한 편집 경로다.
 */
export const SystemPage = () => {
  const { message } = App.useApp();
  const [form] = Form.useForm<AppConfigValues>();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [current, setCurrent] = useState<AppConfigValues | null>(null);

  const load = async () => {
    setLoading(true);
    const { data, error } = await adminClient
      .from("app_config")
      .select()
      .eq("id", 1)
      .maybeSingle();
    if (error) {
      message.error(`app_config 조회 실패: ${error.message}`);
    } else if (data) {
      setCurrent(data as AppConfigValues);
      form.setFieldsValue(data as AppConfigValues);
    }
    setLoading(false);
  };

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const handleSave = async (values: AppConfigValues) => {
    setSaving(true);
    const { error } = await adminClient
      .from("app_config")
      .upsert({ id: 1, ...values, notice: values.notice || null });
    if (error) {
      message.error(`저장 실패: ${error.message}`);
    } else {
      message.success("저장되었습니다 — 이후 앱을 시작하는 사용자부터 즉시 적용됩니다");
      await load();
    }
    setSaving(false);
  };

  // min_build 1 = 게이트 비활성 (모든 빌드 통과).
  const androidActive = (current?.android_min_build ?? 1) > 1;
  const iosActive = (current?.ios_min_build ?? 1) > 1;

  return (
    <Card
      title={
        <Space>
          강제 업데이트
          <Tag color={androidActive ? "red" : "green"}>
            Android {androidActive ? `활성 — ${current?.android_min_build} 미만 차단` : "비활성"}
          </Tag>
          <Tag color={iosActive ? "red" : "green"}>
            iOS {iosActive ? `활성 — ${current?.ios_min_build} 미만 차단` : "비활성"}
          </Tag>
        </Space>
      }
    >
      <Alert
        type="warning"
        showIcon
        style={{ marginBottom: 16 }}
        message="저장 즉시 발동됩니다"
        description={
          <>
            <Paragraph style={{ marginBottom: 4 }}>
              최소 허용 빌드보다 낮은 buildNumber 의 앱은 시작 직후 닫을 수 없는
              업데이트 화면으로 덮이고, 스토어로 이동하는 것 외엔 아무것도 할 수
              없게 됩니다.
            </Paragraph>
            <Paragraph style={{ marginBottom: 0 }}>
              반드시 <Text strong>해당 빌드가 스토어에 게시·전파된 뒤에만</Text> 값을
              올리세요 — 스토어에 새 버전이 없는데 차단부터 하면 사용자는
              업데이트할 방법이 없는 채 잠깁니다.
            </Paragraph>
          </>
        }
      />

      <Paragraph type="secondary" style={{ marginBottom: 24 }}>
        동작 원리 — 앱이 시작할 때 이 설정을 1회 조회해서{" "}
        <Text code>내 buildNumber &lt; 최소 허용 빌드</Text> 이면 강제 업데이트
        게이트를 띄웁니다. 값 <Text code>1</Text> 은 비활성(모든 빌드 통과)이며,
        네트워크 오류로 조회에 실패한 앱은 차단하지 않습니다(fail-open).
        buildNumber 는 버전 표기의 <Text code>+</Text> 뒤 숫자입니다 (예:{" "}
        <Text code>1.0.3+15</Text> → 15).
      </Paragraph>

      {loading ? (
        <Skeleton active />
      ) : (
        <Form form={form} layout="vertical" onFinish={handleSave} style={{ maxWidth: 480 }}>
          <Form.Item
            name="android_min_build"
            label="Android 최소 허용 빌드"
            extra="예: 15 로 저장하면 14 이하 빌드가 전부 차단됩니다. 1 = 비활성."
            rules={[{ required: true, type: "number", min: 1, message: "1 이상의 정수" }]}
          >
            <InputNumber min={1} precision={0} style={{ width: 160 }} />
          </Form.Item>
          <Form.Item
            name="ios_min_build"
            label="iOS 최소 허용 빌드"
            extra="iOS 출시 전까지는 1(비활성)로 둡니다."
            rules={[{ required: true, type: "number", min: 1, message: "1 이상의 정수" }]}
          >
            <InputNumber min={1} precision={0} style={{ width: 160 }} />
          </Form.Item>
          <Form.Item
            name="notice"
            label="게이트 공지 문구 (선택)"
            extra={
              <>
                업데이트 화면 제목 아래에 표시됩니다. 비워두면 기본 문구
                (&ldquo;지금 버전으로는 이용할 수 없습니다. 최신 버전으로 업데이트해
                주세요.&rdquo;)가 나갑니다.
              </>
            }
          >
            <Input.TextArea rows={3} maxLength={200} showCount placeholder="예: 중요한 개선이 포함된 새 버전이 나왔습니다." />
          </Form.Item>
          <Button type="primary" htmlType="submit" loading={saving}>
            저장
          </Button>
        </Form>
      )}
    </Card>
  );
};
