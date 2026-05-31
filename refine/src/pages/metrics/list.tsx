import { DateField, List, ShowButton, useTable } from "@refinedev/antd";
import { useInvalidate, useMany } from "@refinedev/core";
import { Avatar, Modal, Space, Table, Tag, Typography, message } from "antd";
import { adminClient } from "../../providers/data";
import { UserLink } from "../../components/user-link";
import type { AppUser, MetricEntry } from "../../types";
import { parseDemographics } from "../../types";

const { Text } = Typography;

const SOURCE_COLOR: Record<string, string> = {
  camera: "blue",
  album: "green",
};

const GENDER_LABEL: Record<string, string> = {
  male: "남",
  female: "여",
};

export const MetricList = () => {
  const { tableProps, result } = useTable<MetricEntry>({
    syncWithLocation: true,
    sorters: { initial: [{ field: "created_at", order: "desc" }] },
    filters: {
      mode: "server",
    },
  });

  const invalidate = useInvalidate();

  const userIds = (result?.data ?? [])
    .map((m) => m.user_id)
    .filter((v): v is string => !!v);

  const {
    result: { data: usersResult },
    query: { isLoading: usersLoading },
  } = useMany<AppUser>({
    resource: "users",
    ids: Array.from(new Set(userIds)),
    queryOptions: { enabled: userIds.length > 0 },
  });

  const userById = new Map<string, AppUser>(
    (usersResult ?? []).map((u) => [u.id, u])
  );

  const handleCleanup = () => {
    Modal.confirm({
      title: "90일+ 미활동 metrics 삭제",
      content: "updated_at 이 90일 이상 지난 metrics 를 삭제합니다. 되돌릴 수 없습니다.",
      okText: "삭제",
      okButtonProps: { danger: true },
      cancelText: "취소",
      onOk: async () => {
        const cutoff = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000).toISOString();
        // R2 thumbnail 고아 정리는 별개(추후) — 이 버튼은 Supabase row 만 삭제.
        const { data, error } = await adminClient
          .from("metrics")
          .delete()
          .lt("updated_at", cutoff)
          .select("id");
        if (error) {
          message.error(`삭제 실패: ${error.message}`);
          return;
        }
        message.success(`${data?.length ?? 0}건 삭제됨`);
        invalidate({ resource: "metrics", invalidates: ["list"] });
      },
    });
  };

  return (
    <List
      title="metric 업로드"
      headerButtons={({ defaultButtons }) => (
        <>
          {defaultButtons}
          <button
            onClick={handleCleanup}
            style={{
              cursor: "pointer",
              padding: "4px 12px",
              border: "1px solid #d9d9d9",
              borderRadius: 6,
              background: "#fff",
              fontSize: 13,
            }}
          >
            90일+ 미활동 정리
          </button>
        </>
      )}
    >
      <Table {...tableProps} rowKey="id" size="middle" scroll={{ x: 1100 }}>
        <Table.Column<MetricEntry>
          title="업로더"
          dataIndex="user_id"
          render={(uid: string | null) => {
            if (!uid) return <Tag color="default">anon</Tag>;
            const u = userById.get(uid);
            if (usersLoading) return <Text type="secondary">로딩…</Text>;
            if (!u)
              return (
                <Text code style={{ fontSize: 11 }}>
                  {uid.slice(0, 8)}…
                </Text>
              );
            return (
              <Space>
                <Avatar src={u.profile_image_url ?? undefined} size={24}>
                  {u.nickname?.[0] ?? "?"}
                </Avatar>
                <UserLink id={uid}><Text strong>{u.nickname ?? "(없음)"}</Text></UserLink>
              </Space>
            );
          }}
        />
        <Table.Column<MetricEntry>
          title="source"
          dataIndex="body"
          render={(_: unknown, record: MetricEntry) => {
            const v = parseDemographics(record.body).source;
            return v ? <Tag color={SOURCE_COLOR[v] ?? "default"}>{v}</Tag> : <Text type="secondary">-</Text>;
          }}
        />
        <Table.Column<MetricEntry>
          title="성별"
          dataIndex="body"
          render={(_: unknown, record: MetricEntry) => {
            const v = parseDemographics(record.body).gender;
            return v ? GENDER_LABEL[v] ?? v : <Text type="secondary">-</Text>;
          }}
        />
        <Table.Column<MetricEntry>
          title="연령대"
          dataIndex="body"
          render={(_: unknown, record: MetricEntry) => {
            const v = parseDemographics(record.body).ageGroup;
            return v ?? <Text type="secondary">-</Text>;
          }}
        />
        <Table.Column<MetricEntry>
          title="ethnicity"
          dataIndex="body"
          render={(_: unknown, record: MetricEntry) => {
            const v = parseDemographics(record.body).ethnicity;
            return v ? <Text style={{ fontSize: 12 }}>{v}</Text> : <Text type="secondary">-</Text>;
          }}
        />
        <Table.Column<MetricEntry>
          title="본인"
          dataIndex="is_my_face"
          render={(_: unknown, record: MetricEntry) =>
            record.is_my_face ? <Tag color="blue">본인</Tag> : <Text type="secondary">-</Text>
          }
        />
        <Table.Column<MetricEntry>
          title="alias"
          dataIndex="alias"
          render={(v: string | null) =>
            v ? <Text>{v}</Text> : <Text type="secondary">-</Text>
          }
        />
        <Table.Column<MetricEntry>
          title="업로드"
          dataIndex="created_at"
          sorter
          defaultSortOrder="descend"
          render={(v: string) => (
            <DateField value={v} format="YYYY-MM-DD HH:mm" />
          )}
        />
        <Table.Column<MetricEntry>
          title="최종"
          dataIndex="updated_at"
          sorter
          render={(v: string) => (
            <DateField value={v} format="YYYY-MM-DD HH:mm" />
          )}
        />
        <Table.Column<MetricEntry>
          title="조회"
          dataIndex="views"
          sorter
          render={(v: number) => (
            <Text strong={v > 0} type={v > 0 ? undefined : "secondary"}>
              {v}
            </Text>
          )}
        />
        <Table.Column<MetricEntry>
          title="ID"
          dataIndex="id"
          render={(v: string) => (
            <Text code copyable={{ text: v }} style={{ fontSize: 11 }}>
              {v.slice(0, 8)}…
            </Text>
          )}
        />
        <Table.Column<MetricEntry>
          title="해석"
          dataIndex="id"
          fixed="right"
          render={(id: string) => (
            <ShowButton hideText size="small" recordItemId={id} />
          )}
        />
      </Table>
    </List>
  );
};
