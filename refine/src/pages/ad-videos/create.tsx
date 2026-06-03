import { Create } from "@refinedev/antd";
import { useNavigation } from "@refinedev/core";
import {
  Alert,
  Form,
  Input,
  Switch,
  Upload,
  message,
  type UploadFile,
} from "antd";
import { InboxOutlined } from "@ant-design/icons";
import { useState } from "react";
import { adminClient } from "../../providers/data";

interface AdVideoCreateValues {
  title: string;
  active: boolean;
}

export const AdVideoCreate = () => {
  const { list } = useNavigation();
  const [form] = Form.useForm<AdVideoCreateValues>();
  const [file, setFile] = useState<UploadFile | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const handleSubmit = async (values: AdVideoCreateValues) => {
    if (!file?.originFileObj) {
      message.error("mp4 파일을 선택하세요");
      return;
    }
    setSubmitting(true);
    try {
      // 1) storage upload — 'ad_videos' 버킷
      const fileObj = file.originFileObj;
      const ext = fileObj.name.split(".").pop() ?? "mp4";
      const storageName = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`;
      const storagePath = `ad_videos/${storageName}`;
      const { error: upErr } = await adminClient.storage
        .from("ad_videos")
        .upload(storageName, fileObj, {
          contentType: fileObj.type || "video/mp4",
          upsert: false,
        });
      if (upErr) throw new Error(`storage upload: ${upErr.message}`);

      // 2) duration probe (browser HTMLVideoElement)
      const duration = await probeVideoDuration(fileObj).catch(() => null);

      // 3) ad_videos row insert
      const { error: insErr } = await adminClient.from("ad_videos").insert({
        title: values.title,
        storage_path: storagePath,
        duration_sec: duration,
        active: values.active,
      });
      if (insErr) throw new Error(`ad_videos insert: ${insErr.message}`);

      message.success("영상 등록 완료");
      list("ad_videos");
    } catch (e) {
      console.error("[ad_videos create] failed", e);
      message.error(e instanceof Error ? e.message : String(e));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Create
      saveButtonProps={{ onClick: () => form.submit(), loading: submitting }}
      title="영상 광고 추가"
    >
      <Alert
        type="info"
        showIcon
        style={{ marginBottom: 16 }}
        message="mp4 를 'ad_videos' 버킷에 업로드하고 ad_videos 테이블에 행을 추가합니다. 활성 영상은 데일리 무료코인 3편 중 1편으로 노출됩니다."
      />
      <Form
        form={form}
        layout="vertical"
        initialValues={{ active: true }}
        onFinish={handleSubmit}
      >
        <Form.Item
          label="제목"
          name="title"
          rules={[{ required: true, message: "제목을 입력하세요" }]}
        >
          <Input placeholder="예: 브랜드 30초 소개 영상" />
        </Form.Item>

        <Form.Item label="활성" name="active" valuePropName="checked">
          <Switch />
        </Form.Item>

        <Form.Item label="mp4 파일" required>
          <Upload.Dragger
            accept="video/mp4,video/*"
            maxCount={1}
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
            <p className="ant-upload-text">mp4 파일을 끌어다 놓거나 클릭해서 선택</p>
            <p className="ant-upload-hint" style={{ fontSize: 12 }}>
              'ad_videos' 버킷에 업로드되고 public URL 로 Flutter 앱에서 재생됩니다.
            </p>
          </Upload.Dragger>
        </Form.Item>
      </Form>
    </Create>
  );
};

function probeVideoDuration(file: File): Promise<number> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const v = document.createElement("video");
    v.preload = "metadata";
    v.onloadedmetadata = () => {
      const sec = Math.round(v.duration);
      URL.revokeObjectURL(url);
      resolve(sec);
    };
    v.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error("metadata load failed"));
    };
    v.src = url;
  });
}
