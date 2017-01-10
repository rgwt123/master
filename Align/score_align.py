#!/usr/bin/env python

import os
import sys
import argparse
import codecs
import logging
import time
import math
import operator


logger_freq = 2
logger_timestamp = time.time()
logger = logging.getLogger(__file__)

def log_major(message):
	global logger_timestamp
	
	logger.info(message)
	logger_timestamp = time.time()
	
def log_minor(message, major=True):
	global logger_timestamp

	since_last = time.time() - logger_timestamp
	if since_last < logger_freq: return

	logger.info(message)
	logger_timestamp = time.time()

def weight_file_iter(weight_file):
	for line in weight_file:

		tokens = line.strip().split()
		
		src_word = tokens[0]
		trg_word = tokens[1]
		weight = float(tokens[2])

		yield((src_word, trg_word, weight))

def doc_file_bin_iter(doc_file):
	bin_, docs = None, None

	for line in doc_file:
		
		tokens = line.strip().split("\t")

		doc_bin = tokens[0]
		doc_id = tokens[1]
		doc_text = tokens[2]

		if doc_bin != bin_:
			if bin_: yield (bin_, docs)
			bin_, docs = doc_bin, {}

		docs[doc_id] = doc_text

	if bin_: yield (bin_, docs)

def align_file_bin_iter(align_file):
	bin_, aligns = None, None

	for line in align_file:
		
		tokens = line.strip().split("\t")

		align_bin = tokens[0]
		src_doc_id = tokens[1]
		trg_doc_id = tokens[2]
		score = float(tokens[3])

		if align_bin != bin_:
			if bin_: yield (bin_, aligns)
			bin_, aligns = align_bin, {}
		
		src_aligns = aligns.get(src_doc_id, [])
		src_aligns.append((trg_doc_id, score))
		aligns[src_doc_id] = src_aligns

	if bin_: yield (bin_, aligns)

def calc_length_sim(src_doc_text, trg_doc_text, len_mean, len_std):
	# Target length likelihood modeling based on normal distribution.
	# We measure the document length difference by characters, not words.
	
	likelihood = lambda x, m, sd: math.exp(-(((x - m) / float(sd)) ** 2.) / 2.)
	src_len, trg_len = float(len(src_doc_text)), float(len(trg_doc_text))

	length_sim = likelihood(trg_len / src_len, len_mean, len_std)
	return length_sim

def calc_weight_sim(src_doc_text, trg_doc_text, weights):
	src_words, trg_words = src_doc_text.split(), trg_doc_text.split()
	src_size, trg_size = float(len(src_words)), float(len(trg_words))
	null_weights, null_weight = {}, 1e-09

	weight_sim = 1.
	for src_word in src_words:
		
		src_weight = null_weight
		src_weights = weights.get(src_word, null_weights)

		for trg_word in trg_words:
			weight = src_weights.get(trg_word, null_weight)
			src_weight += weight / trg_size

		weight_sim *= src_weight

	return weight_sim

def score_align(align_file, src_doc_file, trg_doc_file, len_mean, len_std, weight_file, output_file):
	# WARNING: Bidirectional weigths decrease precision!
	# Bidirectional weights seem like a good idea but they are not.

	log_major("Loading weights ...")

	weights = {}

	weight_index = 0
	for src_word, trg_word, weight in weight_file_iter(weight_file):

		weight_index += 1
		log_minor("Loading weight %s." % weight_index)

		src_weights = weights.get(src_word, {})
		weights[src_word] = src_weights
		src_weights[trg_word] = weight

	log_major("Weights loaded.")
	log_major("Scoring bins ...")

	align_bin_iter = align_file_bin_iter(align_file)
	src_bin_iter = doc_file_bin_iter(src_doc_file)
	trg_bin_iter = doc_file_bin_iter(trg_doc_file)
	align_item, src_item, trg_item = None, None, None

	align_index = 0
	while True:

		if not align_item: align_item = next(align_bin_iter, None)
		if not src_item: src_item = next(src_bin_iter, None)
		if not trg_item: trg_item = next(trg_bin_iter, None)
		if not align_item or not src_item or not trg_item: break

		align_bin, aligns = align_item
		src_bin, src_docs = src_item
		trg_bin, trg_docs = trg_item

		if align_bin < max(src_bin, trg_bin): align_item = None
		if src_bin < max(align_bin, trg_bin): src_item = None
		if trg_bin < max(align_bin, src_bin): trg_item = None
		if not align_bin == src_bin == trg_bin: continue

		log_major("Scoring bin '%s' ..." % align_bin)

		for src_doc_id, src_aligns in aligns.items():

			align_index += 1
			log_minor("Scoring alignment %s." % align_index)

			new_src_aligns = []
			src_doc_text = src_docs[src_doc_id]

			for trg_doc_id, score in src_aligns:

				trg_doc_text = trg_docs[trg_doc_id]

				length_sim = calc_length_sim(src_doc_text, trg_doc_text, len_mean, len_std)
				weight_sim = calc_weight_sim(src_doc_text, trg_doc_text, weights)
				new_score = length_sim * weight_sim

				new_src_aligns.append((src_bin, src_doc_id, trg_doc_id, new_score))

			new_src_aligns.sort(key=operator.itemgetter(3), reverse=True)

			for new_src_score in new_src_aligns:

				output_row = "\t".join(map(str, new_src_score))
				output_file.write("%s\n" % output_row)

		log_major("Bin '%s' scored." % align_bin)

		align_item, src_item, trg_item = None, None, None

	log_major("All bins scored.")


if __name__ == "__main__":
	logging_format = '>>> [%(filename)s][%(asctime)s] %(message)s'
	logging.basicConfig(stream=sys.stdout, format=logging_format, level=logging.INFO)

	parser = argparse.ArgumentParser(prog=__file__, add_help=False)
	parser.add_argument('-a', '--align', required=True, type=str)
	parser.add_argument('-s', '--src_doc', required=True, type=str)
	parser.add_argument('-t', '--trg_doc', required=True, type=str)
	parser.add_argument('-m', '--len_mean', type=float, default=1.0)
	parser.add_argument('-d', '--len_std', type=float, default=0.5)
	parser.add_argument('-w', '--weight', required=True, type=str)
	parser.add_argument('-o', '--output', required=True, type=str)
	args = parser.parse_args()

	log_major("Starting execution in %s." % os.getcwd())
	for arg in vars(args): log_major("Option --%s = %s." % (arg, getattr(args, arg)))

	align_file = codecs.open(args.align, "r", "utf-8")
	src_doc_file = codecs.open(args.src_doc, "r", "utf-8")
	trg_doc_file = codecs.open(args.trg_doc, "r", "utf-8")
	weight_file = codecs.open(args.weight, "r", "utf-8")
	output_file = codecs.open(args.output, "w", "utf-8")

	try:
		score_align(align_file, src_doc_file, trg_doc_file, 
			args.len_mean, args.len_std, weight_file, output_file)

		log_major("Script ended successfully.")
	except:
		log_major("Script ended unsucessfully!")
	finally:
		align_file.close()
		src_doc_file.close()
		trg_doc_file.close()
		weight_file.close()
		output_file.close()