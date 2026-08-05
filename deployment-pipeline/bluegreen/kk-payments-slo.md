# kk-payments SLI and SLO Document

This document defines the proposed service-level indicators and objectives for kk-payments. The targets below are simulator-informed and should be treated as proposed target (not yet measured against production traffic) until enough real traffic has been observed.

## 1) Availability SLI

**What we measure**: Request availability for the payment service.

**Data source**: Nginx access logs plus the `/health` endpoint. The access logs show whether payment requests returned a successful HTTP response, and the health endpoint is used as a synthetic probe to confirm the service is reachable.

**Calculation method**: `availability = successful requests / total requests`, where a successful request is any payment request that returns a 2xx or 3xx response and a failed request is any request that returns 5xx, times out, or fails the health probe. The numerator and denominator are counted separately for the same window.

**Measurement window**: Rolling 5-minute operational window for SLI evaluation, rolled up into a 30-day SLO window.

**SLO target**: proposed target (not yet measured against production traffic) - at least 99.9% availability over a 30-day measurement window.

## 2) Latency SLI

**What we measure**: End-to-end payment API response latency.

**Data source**: Nginx access logs, specifically the upstream or request timing fields that capture how long the payment request took from the proxy point of view.

**Calculation method**: `latency SLI = percentage of requests completed under the latency budget`. For this specification, a request is successful for latency if its recorded request time is at or below 800 ms. The SLI is the share of all measured requests within the window that meet that budget.

**Measurement window**: Rolling 15-minute operational window for SLI evaluation, rolled up into a 30-day SLO window.

**SLO target**: proposed target (not yet measured against production traffic) - at least 95% of payment requests complete within 800 ms over a 30-day measurement window.

## 3) Payment Error Rate SLI

**What we measure**: Rate of payment attempts that fail due to application or downstream payment-processing errors.

**Data source**: A hypothetical metrics system backed by application instrumentation. The service would emit counters such as `kk_payments_attempt_total`, `kk_payments_success_total`, and `kk_payments_error_total`, and the metrics system would expose them for aggregation.

**Calculation method**: `payment error rate = payment errors / total payment attempts`, where payment errors include application exceptions, explicit payment rejections returned by kk-payments, and downstream gateway failures that the service records as failed attempts.

**Measurement window**: Rolling 15-minute operational window for SLI evaluation, rolled up into a 30-day SLO window.

**SLO target**: proposed target (not yet measured against production traffic) - no more than 0.5% payment error rate over a 30-day measurement window, which is equivalent to at least 99.5% successful payment attempts.

## Rollback Thresholds

The thresholds below are the short-window signals that trigger an automated rollback during blue-green deployment. Each threshold is intentionally stricter than the 30-day SLO so the system rolls back before a sustained degradation can consume the full objective budget.

| SLI | 30-day SLO target | Short-window rollback threshold | Relationship to the SLO target |
| --- | --- | --- | --- |
| Availability | proposed target (not yet measured against production traffic) - 99.9% | 5-minute availability drops below 99.0% or two consecutive failed health probes | The rollback threshold is 0.9 percentage points below the SLO target, giving a buffer for transient noise while still reacting to real outages. |
| Latency | proposed target (not yet measured against production traffic) - 95% of requests under 800 ms | 5-minute p95 latency exceeds 1,200 ms | The rollback threshold is 400 ms above the latency budget, so the release is rejected when response time drifts far enough above the SLO to be operationally risky. |
| Payment error rate | proposed target (not yet measured against production traffic) - no more than 0.5% errors | 5-minute payment error rate exceeds 2.0% | The rollback threshold is 1.5 percentage points worse than the 30-day error budget, which keeps the release from continuing once errors are materially elevated. |

## What We Do Not Commit To

We do not commit to checkout conversion rate. That metric is influenced by pricing, customer behavior, and kijani-kiosk flow design, so it is adjacent to kk-payments but not a service-level guarantee.

We do not commit to frontend page-load time. That metric depends on browser performance, kiosk hardware, and asset delivery, so it is outside the scope of the payment service itself.