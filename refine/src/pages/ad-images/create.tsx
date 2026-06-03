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
import { useState } from "react";
import { adminClient } from "../../providers/data";

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
    setSubmitting(true);
    try {
      // 1) storage upload — 'ad_images' 버킷
      const fileObj = file.originFileObj;
      const ext = fileObj.name.split(".").pop() ?? "jpg";
      const storageName = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`;
      const storagePath = `ad_images/${storageName}`;
      const { error: upErr } = await adminClient.storage
        .from("ad_images")
        .upload(storageName, fileObj, {
          contentType: fileObj.type || "image/jpeg",
          upsert: false,
        });
      if (upErr) throw new Error(`storage upload: ${upErr.message}`);

      // 2) ad_images row insert
      const { error: insErr } = await adminClient.from("ad_images").insert({
        title: values.title,
        storage_path: storagePath,
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
        message="이미지를 'ad_images' 버킷에 업로드하고 ad_images 테이블에 행을 추가합니다. 활성 배너는 홈 탭 상단에서 sort_order 순으로 rotation 노출되고, 탭하면 link_url 로 이동합니다."
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
              'ad_images' 버킷에 업로드되고 public URL 로 홈 배너에 표시됩니다.
            </p>
          </Upload.Dragger>
        </Form.Item>
      </Form>
    </Create>
  );
};
