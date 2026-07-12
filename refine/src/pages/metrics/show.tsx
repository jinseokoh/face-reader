import { Show } from "@refinedev/antd";
import { useShow } from "@refinedev/core";
import { Alert, Avatar, Descriptions, Space, Tag, Typography } from "antd";
import { useMemo } from "react";
import type { MetricEntry } from "../../types";
import { metricThumbUrl, parseDemographics } from "../../types";
import { runEngine, type EngineOutput } from "../../lib/share-engine";
import { SoloHeroCard } from "./HeroCard";

const { Text } = Typography;

const SOURCE_COLOR: Record<string, string> = { camera: "blue", album: "green" };
const GENDER_LABEL: Record<string, string> = { male: "남", female: "여" };

export const MetricShow = () => {
  const { query } = useShow<MetricEntry>();
  const row = query?.data?.data;

  const result = useMemo<{ eng?: EngineOutput; error?: string }>(() => {
    if (!row?.body) return {};
    try {
      return { eng: runEngine(row.body) };
    } catch (e) {
      return { error: e instanceof Error ? e.message : String(e) };
    }
  }, [row?.body]);

  return (
    <Show isLoading={query.isLoading} title="관상 해석">
      {row && (
        <Space direction="vertical" size="large" style={{ width: "100%" }}>
          <Descriptions column={2} bordered size="small">
            <Descriptions.Item label="썸네일" span={2}>
              <Avatar
                src={metricThumbUrl(row.body) ?? undefined}
                size={72}
                shape="circle"
              >
                {row.alias?.[0] ?? "?"}
              </Avatar>
            </Descriptions.Item>
            <Descriptions.Item label="ID">
              <Text code copyable={{ text: row.id }} style={{ fontSize: 12 }}>
                {row.id}
              </Text>
            </Descriptions.Item>
            <Descriptions.Item label="user_id">
              <Text code style={{ fontSize: 12 }}>
                {row.user_id ?? "anon"}
              </Text>
            </Descriptions.Item>
            {(() => {
              const d = parseDemographics(row.body);
              return (
                <>
                  <Descriptions.Item label="source">
                    <Tag color={SOURCE_COLOR[d.source ?? ""] ?? "default"}>{d.source ?? "-"}</Tag>
                  </Descriptions.Item>
                  <Descriptions.Item label="ethnicity">{d.ethnicity ?? "-"}</Descriptions.Item>
                  <Descriptions.Item label="성별">{GENDER_LABEL[d.gender ?? ""] ?? d.gender ?? "-"}</Descriptions.Item>
                  <Descriptions.Item label="연령대">{d.ageGroup ?? "-"}</Descriptions.Item>
                </>
              );
            })()}
            <Descriptions.Item label="본인">
              {row.is_my_face ? <Tag color="blue">본인</Tag> : "-"}
            </Descriptions.Item>
            <Descriptions.Item label="alias">{row.alias ?? "-"}</Descriptions.Item>
            <Descriptions.Item label="조회수">{row.views}</Descriptions.Item>
            <Descriptions.Item label="created_at">{row.created_at}</Descriptions.Item>
            <Descriptions.Item label="updated_at">{row.updated_at}</Descriptions.Item>
          </Descriptions>

          {result.error && (
            <Alert
              type="error"
              showIcon
              message="엔진 실행 실패"
              description={
                <Text code style={{ whiteSpace: "pre-wrap" }}>
                  {result.error}
                </Text>
              }
            />
          )}

          {result.eng && <SoloHeroCard eng={result.eng} />}

          {row.body && (
            <details>
              <summary style={{ cursor: "pointer", fontWeight: 600 }}>
                raw body
              </summary>
              <pre
                style={{
                  fontSize: 11,
                  background: "#fafafa",
                  padding: 12,
                  borderRadius: 6,
                  overflow: "auto",
                  maxHeight: 360,
                }}
              >
                {prettify(row.body)}
              </pre>
            </details>
          )}
        </Space>
      )}
    </Show>
  );
};

function prettify(json: string): string {
  try {
    return JSON.stringify(JSON.parse(json), null, 2);
  } catch {
    return json;
  }
}
