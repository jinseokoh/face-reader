import { Create } from "@refinedev/antd";
import { useNavigation } from "@refinedev/core";
import {
  Alert,
  Form,
  Input,
  InputNumber,
  Switch,
  Upload,
  message,
  type UploadFile,
} from "antd";
import { InboxOutlined } from "@ant-design/icons";
import { AwsClient } from "aws4fetch";
import { useState } from "react";
import { adminClient } from "../../providers/data";

// 배너 이미지는 R2(facely/banners/)에 직접 PUT 한다 (모바일 썸네일과 동일하게
// R2 직통). refine 는 로컬 전용 admin 이라 R2 키를 .env 에 둬도 노출 위험 없음.
// 브라우저 PUT 이므로 R2 버킷 CORS 에 이 origin(PUT)을 허용해야 한다.
const R2_ENV = (import.meta as { env: Record<string, string> }).env;
const R2 = {
  accountId: R2_ENV.VITE_R2_ACCOUNT_ID,
  bucket: R2_ENV.VITE_R2_BUCKET_NAME || "facely",
  accessKeyId: R2_ENV.VITE_R2_ACCESS_KEY_ID,
  secretAccessKey: R2_ENV.VITE_R2_SECRET_ACCESS_KEY,
};

interface AdImageCreateValues {
  title: string;
  link_url?: string;
  sort_order: number;
  active: boolean;
}

export const AdImageCreate = () => {
  const { list } = useNavigation();
  const [form] = Form.useForm<AdImageCreateValues>();
  const [file, setFile] = useState<UploadFile | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const handleSubmit = async (values: AdImageCreateValues) => {
    if (!file?.originFileObj) {
      message.error("이미지 파일을 선택하세요");
      return;
    }
    if (!R2.accountId || !R2.accessKeyId || !R2.secretAccessKey) {
      message.error("R2 환경변수(VITE_R2_*)가 .env 에 설정되지 않았습니다");
      return;
    }
    setSubmitting(true);
    try {
      // 1) R2 직접 PUT — facely/banners/{uuid}.{ext}. host 만 서명(signQuery)하고
      //    content-type 은 자유. key 를 ad_images.storage_path 로 저장.
      const fileObj = file.originFileObj;
      const ext = (fileObj.name.split(".").pop() || "png").toLowerCase();
      const key = `banners/${crypto.randomUUID()}.${ext}`;
      const client = new AwsClient({
        accessKeyId: R2.accessKeyId,
        secretAccessKey: R2.secretAccessKey,
        service: "s3",
        region: "auto",
      });
      const objectUrl = `https://${R2.accountId}.r2.cloudflarestorage.com/${R2.bucket}/${key}`;
      const signed = await client.sign(
        new Request(objectUrl, { method: "PUT" }),
        { aws: { signQuery: true } },
      );
      const putRes = await fetch(signed.url, {
        method: "PUT",
        body: fileObj,
        headers: { "Content-Type": fileObj.type || "image/png" },
      });
      if (!putRes.ok) {
        throw new Error(`R2 업로드 실패 (${putRes.status})`);
      }

      // 2) ad_images row insert (storage_path = R2 key)
      const { error: insErr } = await adminClient.from("ad_images").insert({
        title: values.title,
        storage_path: key,
        link_url: values.link_url?.trim() || null,
        sort_order: values.sort_order,
        active: values.active,
      });
      if (insErr) throw new Error(`ad_images insert: ${insErr.message}`);

      message.success("배너 등록 완료");
      list("ad_images");
    } catch (e) {
      console.error("[ad_images create] failed", e);
      message.error(e instanceof Error ? e.message : String(e));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Create
      saveButtonProps={{ onClick: () => form.submit(), loading: submitting }}
      title="배너 광고 추가"
    >
      <Alert
        type="info"
        showIcon
        style={{ marginBottom: 16 }}
        message="이미지를 R2(facely/banners/)에 업로드하고 ad_images 테이블에 행을 추가합니다. 활성 배너는 홈 탭 상단에서 sort_order 순으로 rotation 노출되고, 탭하면 link_url 로 이동합니다."
      />
      <Form
        form={form}
        layout="vertical"
        initialValues={{ sort_order: 0, active: true }}
        onFinish={handleSubmit}
      >
        <Form.Item
          label="제목 (관리용)"
          name="title"
          rules={[{ required: true, message: "제목을 입력하세요" }]}
        >
          <Input placeholder="예: ○○브랜드 5월 배너" />
        </Form.Item>

        <Form.Item
          label="link_url (탭 시 이동, 비우면 비탭)"
          name="link_url"
          rules={[{ type: "url", message: "올바른 URL 형식이 아닙니다", warningOnly: false }]}
        >
          <Input placeholder="https://example.com/promo" />
        </Form.Item>

        <Form.Item
          label="노출 순서 (작을수록 먼저)"
          name="sort_order"
          rules={[{ required: true, type: "integer", min: 0 }]}
        >
          <InputNumber min={0} step={1} style={{ width: 120 }} />
        </Form.Item>

        <Form.Item label="활성" name="active" valuePropName="checked">
          <Switch />
        </Form.Item>

        <Form.Item label="이미지 파일" required>
          <Upload.Dragger
            accept="image/*"
            maxCount={1}
            listType="picture"
            beforeUpload={() => false}
            fileList={file ? [file] : []}
            onChange={(info) => {
              const last = info.fileList[info.fileList.length - 1];
              setFile(last ?? null);
            }}
          >
            <p className="ant-upload-drag-icon">
              <InboxOutlined />
            </p>
            <p className="ant-upload-text">이미지를 끌어다 놓거나 클릭해서 선택</p>
            <p className="ant-upload-hint" style={{ fontSize: 12 }}>
              R2(facely/banners/)에 업로드되고 cdn.facely.kr 로 홈 배너에 표시됩니다.
            </p>
          </Upload.Dragger>
        </Form.Item>
      </Form>
    </Create>
  );
};
