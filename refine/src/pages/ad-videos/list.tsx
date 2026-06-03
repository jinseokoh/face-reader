import { CreateButton, DateField, List, useTable } from "@refinedev/antd";
import { Space, Switch, Table, Typography, message } from "antd";
import { adminClient } from "../../providers/data";
import type { AdVideo } from "../../types";

const { Text } = Typography;

// 영상은 R2(cdn.facely.kr)에 있다. storage_path 예: "banners/{uuid}.mp4".
const CDN_BASE = (
  (import.meta as { env: Record<string, string> }).env.VITE_R2_CDN_BASE ||
  "https://cdn.facely.kr"
).replace(/\/$/, "");

export const AdVideoList = () => {
  const { tableProps, tableQuery } = useTable<AdVideo>({
    resource: "ad_videos",
    syncWithLocation: true,
    sorters: { initial: [{ field: "created_at", order: "desc" }] },
  });

  const toggleActive = async (id: string, active: boolean) => {
    const { error } = await adminClient
      .from("ad_videos")
      .update({ active })
      .eq("id", id);
    if (error) {
      message.error(`상태 변경 실패: ${error.message}`);
      return;
    }
    message.success(`${active ? "활성화" : "비활성화"} 완료`);
    tableQuery.refetch();
  };

  return (
    <List title="영상 광고" headerButtons={<CreateButton>영상 추가</CreateButton>}>
      <Table {...tableProps} rowKey="id" size="middle">
        <Table.Column<AdVideo>
          title="제목"
          dataIndex="title"
          render={(v: string) => <Text strong>{v}</Text>}
        />
        <Table.Column<AdVideo>
          title="storage_path"
          dataIndex="storage_path"
          render={(v: string) => (
            <Space size={4}>
              <Text code style={{ fontSize: 11 }}>
                {v}
              </Text>
              {CDN_BASE && (
                <a
                  href={`${CDN_BASE}/${v}`}
                  target="_blank"
                  rel="noreferrer"
                  style={{ fontSize: 11 }}
                >
                  열기
                </a>
              )}
            </Space>
          )}
        />
        <Table.Column<AdVideo>
          title="길이"
          dataIndex="duration_sec"
          render={(v: number | null) =>
            v == null ? "-" : `${Math.floor(v / 60)}:${String(v % 60).padStart(2, "0")}`
          }
        />
        <Table.Column<AdVideo>
          title="활성"
          dataIndex="active"
          render={(v: boolean, row: AdVideo) => (
            <Switch
              checked={v}
              size="small"
              onChange={(checked) => toggleActive(row.id, checked)}
            />
          )}
        />
        <Table.Column<AdVideo>
          title="등록"
          dataIndex="created_at"
          sorter
          defaultSortOrder="descend"
          render={(v: string) => <DateField value={v} format="YYYY-MM-DD HH:mm" />}
        />
      </Table>
    </List>
  );
};
