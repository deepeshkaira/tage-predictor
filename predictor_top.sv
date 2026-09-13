.current_LFSR_value_input    (lfsr_state_o),
.table_empty_mask_i          (table_empty_mask),
.commit_base_idx_i           (commit_base_index),
.commit_tagged_indices_i     (commit_tagged_indices),
.commit_tagged_tags_i        (commit_tagged_tags),
.base_update_en_o            (base_update_en),
.base_update_idx_o           (base_update_index),
.tagged_table_update_en_o    (tagged_update_en),
.table_cmd_o                 (tagged_update_cmd),
.update_tagged_indices_o     (tagged_update_indices),
.update_tagged_tags_o        (tagged_update_tags)
);

// ---------------------------------------------------------------------
// Base table.
// ---------------------------------------------------------------------

logic [DISTANCE_WIDTH-1:0]  base_read_dist;
logic [BASE_CONF_WIDTH-1:0] base_read_conf;

base_table_wrapper #(
.INDEX_WIDTH      (BASE_INDEX_WIDTH),
.DISTANCE_WIDTH   (DISTANCE_WIDTH),
.CONFIDENCE_WIDTH (BASE_CONF_WIDTH)
) u_base_table (
.clk                    (clk),
.fetch_en_i             (table_read_en),
.fetch_idx_i            (fetch_base_index_o),
.read_dist_o            (base_read_dist),
.read_conf_o            (base_read_conf),
.update_en_i            (base_update_en),
.commit_mispredicted_i  (commit_mispredicted_i),
.commit_idx_i           (base_update_index),
.commit_old_dist_i      (commit_base_old_dist_i),
.commit_old_conf_i      (commit_base_old_conf_i),
.commit_new_dist_i      (commit_true_distance_i)
);

assign base_confidence_o = base_read_conf;

// ---------------------------------------------------------------------
// Tagged tables, comparators, and per-table hit muxes.
// ---------------------------------------------------------------------

logic [TAG_WIDTH-1:0]      tagged_read_tags [0:NUM_TAGGED-1][NUM_WAYS];
logic [DISTANCE_WIDTH-1:0] tagged_read_dists [0:NUM_TAGGED-1][NUM_WAYS];
logic [TAG_CONF_WIDTH-1:0] tagged_read_confs [0:NUM_TAGGED-1][NUM_WAYS];
logic [USEFUL_WIDTH-1:0]   tagged_read_useful [0:NUM_TAGGED-1][NUM_WAYS];
logic [NUM_TAGGED-1:0]     table_hit_vector;

generate
for (genvar t = 0; t < NUM_TAGGED; t++) begin : gen_tagged_tables
	tagged_table_wrapper #(
		.INDEX_WIDTH      (TAG_INDEX_WIDTH),
		.NUM_WAYS         (NUM_WAYS),
		.TAG_WIDTH        (TAG_WIDTH),
		.DISTANCE_WIDTH   (DISTANCE_WIDTH),
		.CONFIDENCE_WIDTH (TAG_CONF_WIDTH),
		.USEFUL_WIDTH     (USEFUL_WIDTH)
	) u_tagged_table (
		.clk                     (clk),
		.fetch_en_i              (table_read_en),
		.fetch_idx_i             (fetch_tagged_indices_o[t]),
		.read_tags_o             (tagged_read_tags[t]),
		.read_dists_o            (tagged_read_dists[t]),
		.read_confs_o            (tagged_read_confs[t]),
		.read_useful_o           (tagged_read_useful[t]),
		.update_en_i             (tagged_update_en[t]),
		.update_cmd_i            (tagged_update_cmd[t]),
		.commit_idx_i            (tagged_update_indices[t]),
		.commit_empty_ways_i     (commit_empty_way_masks_i[t]),
		.commit_hit_way_id_i     (commit_hit_way_ids_i[t]),
		.commit_old_tag_i        (commit_old_tags_i[t]),
		.commit_old_dist_i       (commit_old_dists_i[t]),
		.commit_old_conf_i       (commit_old_confs_i[t]),
		.commit_old_useful_i     (commit_old_useful_i[t]),
		.commit_new_tag_i        (tagged_update_tags[t]),
		.commit_new_dist_i       (commit_true_distance_i)
	);

	tagged_way_comparator #(
		.NUM_WAYS  (NUM_WAYS),
		.TAG_WIDTH (TAG_WIDTH)
	) u_comparator (
		.fetch_en_i      (prediction_valid_o),
		.hashed_tag_i    (fetch_tagged_tags_o[t]),
		.read_tags_i     (tagged_read_tags[t]),
		.way_hit_flag    (table_hit_vector[t]),
		.way_hit_vector_o(fetch_way_hit_vectors_o[t])
	);

	tagged_hit_mux #(
		.NUM_WAYS         (NUM_WAYS),
		.DISTANCE_WIDTH   (DISTANCE_WIDTH),
		.CONFIDENCE_WIDTH (TAG_CONF_WIDTH),
		.USEFUL_WIDTH     (USEFUL_WIDTH),
		.WAY_ID_WIDTH     (WAY_ID_WIDTH)
	) u_hit_mux (
		.way_hit_vector_i (fetch_way_hit_vectors_o[t]),
		.read_dists_i     (tagged_read_dists[t]),
		.read_confs_i     (tagged_read_confs[t]),
		.read_useful_i    (tagged_read_useful[t]),
		.hit_dist_o       (fetch_provider_dists_o[t]),
		.hit_conf_o       (fetch_provider_confs_o[t]),
		.hit_useful_o     (fetch_provider_useful_o[t]),
		.hit_way_id_o     (fetch_provider_way_ids_o[t])
	);

	always_comb begin
		fetch_provider_tags_o[t] = '0;
		fetch_empty_way_masks_o[t] = '0;
		for (int w = 0; w < NUM_WAYS; w++) begin
			fetch_provider_tags_o[t] |=
				tagged_read_tags[t][w]
				& {TAG_WIDTH{fetch_way_hit_vectors_o[t][w]}};
			fetch_empty_way_masks_o[t][w] =
				~(|tagged_read_useful[t][w]);
		end
	end
end
endgenerate

assign fetch_table_hit_vector_o = table_hit_vector;

// ---------------------------------------------------------------------
// Final provider selection.
// ---------------------------------------------------------------------

final_priority_encoder_mux #(
.NUM_TAGGED_TABLES (NUM_TAGGED),
.DISTANCE_WIDTH    (DISTANCE_WIDTH),
.PROVIDER_ID_WIDTH (PROVIDER_ID_WIDTH)
) u_final_select (
.table_hit_vector_i (table_hit_vector),
.tagged_dists_i     (fetch_provider_dists_o),
.base_dist_i        (base_read_dist),
.final_dist_o       (predicted_distance_o),
.provider_id_o      (provider_id_o)
);

always_ff @(posedge clk or negedge rst_n) begin
if (!rst_n) begin
	prediction_valid_o <= 1'b0;
end else begin
	prediction_valid_o <= table_read_en;
end
end

always_comb begin
provider_confidence_o = '0;
provider_useful_o     = '0;
provider_way_id_o     = '0;

if (provider_id_o != '0) begin
	provider_confidence_o =
		fetch_provider_confs_o[provider_id_o-1'b1];
	provider_useful_o =
		fetch_provider_useful_o[provider_id_o-1'b1];
	provider_way_id_o =
		fetch_provider_way_ids_o[provider_id_o-1'b1];
end
end

endmodule
