import { CreateButton, DateField, List, useTable } from "@refinedev/antd";
import { App, Image, Space, Switch, Table, Typography } from "antd";
import { adminClient } from "../../providers/data";
import type { AdImage } from "../../types";

const { Text } = Typography;

// 배너는 R2(cdn.facely.kr)에 있다. storage_path 예: "banners/{uuid}.png".
const CDN_BASE = (
  (import.meta as { env: Record<string, string> }).env.VITE_R2_CDN_BASE ||
  "https://cdn.facely.kr"
).replace(/\/$/, "");

const publicUrl = (storagePath: string) => `${CDN_BASE}/${storagePath}`;

export const AdImageList = () => {
  const { message } = App.useApp();
  const { tableProps, tableQuery } = useTable<AdImage>({
    resource: "ad_images",
    syncWithLocation: true,
    sorters: { initial: [{ field: "sort_order", order: "asc" }] },
  });

  const toggleActive = async (id: string, active: boolean) => {
    const { error } = await adminClient
      .from("ad_images")
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
    <List title="배너 광고" headerButtons={<CreateButton>배너 추가</CreateButton>}>
      <Table {...tableProps} rowKey="id" size="middle">
        <Table.Column<AdImage>
          title="미리보기"
          dataIndex="storage_path"
          render={(v: string) =>
            CDN_BASE ? (
              <Image
                src={publicUrl(v)}
                width={80}
                height={48}
                style={{ objectFit: "cover", borderRadius: 4 }}
              />
            ) : (
              <Text code style={{ fontSize: 11 }}>
                {v}
              </Text>
            )
          }
        />
        <Table.Column<AdImage>
          title="제목"
          dataIndex="title"
          render={(v: string) => <Text strong>{v}</Text>}
        />
        <Table.Column<AdImage>
          title="link_url"
          dataIndex="link_url"
          render={(v: string | null) =>
            v ? (
              <a href={v} target="_blank" rel="noreferrer" style={{ fontSize: 12 }}>
                {v}
              </a>
            ) : (
              <Text type="secondary">—</Text>
            )
          }
        />
        <Table.Column<AdImage>
          title="순서"
          dataIndex="sort_order"
          sorter
          render={(v: number) => <Text>{v}</Text>}
        />
        <Table.Column<AdImage>
          title="활성"
          dataIndex="active"
          render={(v: boolean, row: AdImage) => (
            <Switch
              checked={v}
              size="small"
              onChange={(checked) => toggleActive(row.id, checked)}
            />
          )}
        />
        <Table.Column<AdImage>
          title="등록"
          dataIndex="created_at"
          render={(v: string) => <DateField value={v} format="YYYY-MM-DD HH:mm" />}
        />
      </Table>
    </List>
  );
};
