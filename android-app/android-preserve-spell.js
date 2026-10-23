// Keep the v1.0.14 spelling library, practice tabs, and its due review queue.
const androidReviewWithWordRows=reviewView;
reviewView=function(only=module==='review'?'':module,onlyKey=''){
 if(module==='spell'&&only==='spell')return '';
 return androidReviewWithWordRows(only,onlyKey);
};
